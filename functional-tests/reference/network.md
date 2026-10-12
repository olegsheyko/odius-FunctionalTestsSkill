# Сетевые тесты (CQTest + PIE), роли и смена

Файлы: `MPNetTavernCoopTest.cpp` (классы тестов), `MPNetCoopPlayer.h/.cpp` (игрок в своём мире: роли, работник смены), `MPMapNetworkComponent.h` (PIE-сеть на нашей карте, окна, видео), `MPShiftBoard.h/.cpp` (доска задач).

## Как устроено (коротко)
- Listen server + N клиентов в одном процессе полного редактора, между ними настоящий `NetDriver`. Запуск — только `UnrealEditor.exe` (`run-tests.ps1` выбирает сам).
- `FMPMapNetworkComponent` грузит нашу карту (движковый компонент всегда делает пустую) и строит последовательность Stop PIE → LoadMap → Start PIE → SetWorlds → PacketSettings → Connect → AwaitClientsReady → раскладка окон/видео.
- Каждый игрок — `AMPNetCoopPlayer`, заспавненный в мир своей машины: `AMPNetCoopPlayer::StartIn(World, NavWorld=Server, Role, Name, bMakeRoom)`. Он берёт локального игрока этого мира и играет через его ввод; клиентские действия уходят на сервер RPC игры.
- Сценарий идёт под «внешним раннером» (`StartUnderExternalRunner`): `AFunctionalTest::FinishTest/RunTest` нельзя звать внутри CQTest (static_cast к чужому типу). Итог читается `IsScenarioRunning()` / `HasScenarioSucceeded()`.
- Пути строятся по навмешу сервера (`NavigationWorld`): у клиентов навигации нет.
- Ключ объекта, одинаковый на всех машинах — `NetKey(Actor)` (NetGUID); имена акторов на сервере и клиенте разные.
- Перед стартом — `MPNetCoop::ExpectKnownNoise(TestRunner)` (CQTest пропускает тест при ранней ошибке лога).

## Шаблон нового сетевого теста

```cpp
NETWORK_TEST_CLASS(MPNetXxx, "Project.Network.Xxx")
{
	FMPMapNetworkComponent<FBasePIENetworkComponentState> Network{ TestRunner, TestCommandBuilder, bInitializing, MPNetCoop::MapPath };
	TArray<TWeakObjectPtr<AMPNetCoopPlayer>> Players;
	double ConvergeStart = 0.0;

	BEFORE_EACH()
	{
		MPNetCoop::ExpectKnownNoise(TestRunner);
		FNetworkComponentBuilder<FBasePIENetworkComponentState>()
			.WithClients(3)                 // клиенты, без listen server
			.AsListenServer()
			.WithGameInstanceClass(UGameInstance::StaticClass())
			.WithGameMode(MPNetCoop::GameMode())
			// .WithPacketSimulationSettings(MPNetCoop::BadNetwork())   // плохая сеть, см. MPNetTavernCoop4Lag
			.Build(Network);
	}

	TEST_METHOD(FourPlayers_ListenServer_Xxx)
	{
		Network
			.Then(TEXT("Seat the players"), [this]()
			{
				AMPNetCoopPlayer::ResetTeamBoard();
				UWorld* Server = Network.Server().World;
				Players.Add(AMPNetCoopPlayer::StartIn(Server, Server, EMPCoopRole::Stoker, TEXT("Stoker_ListenServer"), false));
				Players.Add(AMPNetCoopPlayer::StartIn(Network.Client(0).World, Server, EMPCoopRole::Host, TEXT("Host_Client1"), false));
				// ...
				for (const TWeakObjectPtr<AMPNetCoopPlayer>& Player : Players) ASSERT_THAT(IsTrue(Player.IsValid()));
			})
			.Until(TEXT("Play"), [this]() { return MPNetCoop::AllFinished(Players); }, FTimespan::FromMinutes(16))
			.Until(TEXT("Let the clients catch up with the server"), [this]()
			{
				// Своим таймером, не таймаутом шага: дать репликации 15 с, потом сравнить в любом случае.
				if (ConvergeStart == 0.0) ConvergeStart = FPlatformTime::Seconds();
				const FString Server = MPNetCoop::TavernSnapshot(Network.Server().World);
				bool bSame = true;
				for (int32 Index = 0; Index < Network.NumClients(); ++Index) bSame &= MPNetCoop::TavernSnapshot(Network.Client(Index).World) == Server;
				return bSame || FPlatformTime::Seconds() - ConvergeStart > 15.0;
			}, FTimespan::FromSeconds(30))
			.Then(TEXT("Every machine sees the same"), [this]()
			{
				for (int32 Index = 0; Index < Network.NumClients(); ++Index)
					ASSERT_THAT(AreEqual(MPNetCoop::TavernSnapshot(Network.Server().World), MPNetCoop::TavernSnapshot(Network.Client(Index).World)));
			})
			.Then(TEXT("Every player finished their part"), [this]()
			{
				for (const TWeakObjectPtr<AMPNetCoopPlayer>& Player : Players) ASSERT_THAT(IsTrue(Player.IsValid() && Player->HasScenarioSucceeded()));
			});
	}
};
```
Если снимок должен включать новое состояние — расширь `MPNetCoop::TavernSnapshot` (только реплицируемые поля!).

## Новая роль
1. Значение в `EMPCoopRole` (`MPNetCoopPlayer.h`).
2. Шаги роли — метод `AddXxxRole(Timeout)` в `AMPTavernTestBase` (чтобы локальный кооп мог использовать тот же сценарий), координация через состояние игры / `TellTeamWhatToBrew`.
3. `case` в `AMPNetCoopPlayer::BuildScenario`.

## Новое дело в смене (`ShiftWorker`)
1. Условие и приоритет — в `AMPNetCoopPlayer::PickTask()` (порядок блоков = приоритет). Условие должно опираться на то, что видит машина игрока (реплицируемое), и проверять, что результат действия игра примет (найди в C++ условия отказа).
2. Захват `Board.TryClaim(TEXT("Kind:<ключ>"), Me)` — чтобы двое не делали одно (ключ объекта — `NetKey`). Ограничивай число исполнителей реальной ёмкостью (пример: носильщиков сусла ≤ места в ферментере).
3. `StartTask(TEXT("Kind"), TEXT("Человеческое название"), [this]() { ...шаги...; })` — по завершении (или отказу) захваты освобождаются, время считается, затем снова «Look for work».
4. Внутри — шаги-проверки «ещё актуально?» с `AbandonTask("почему")` перед каждым действием, которое может стать бессмысленным.
5. Тупики внутри дела (застрял, недостижимо, таймаут шага) при `bTasksMayGiveUp` бросают дело и пишутся в `GiveUps` — тест падает, если их больше `max(3, дел/5)`.
6. Предметы, которые надо положить, — на `OpenSpotNear(...)` (не в проходах).

## Что знать про репликацию
- Теги актора не реплицируются (`MP.Wort` только на сервере) — определяй предметы по реплицируемым компонентам (`UPotionIdentityComponent`).
- Перед ожиданием на клиенте проверь `DOREPLIFETIME` поля в игре. Не реплицируется → на клиенте ждать нельзя (и это может быть баг игры — проверь, нужна ли клиенту эта информация).
- Серверная проверка действия клиента идёт серверной трассой с позицией, устаревшей на пинг: предусматривай повтор действия, как живой игрок.
- Плохая сеть: `PktLagMin 60, PktLagMax 90, PktLoss 1` на каждом драйвере (пинг ~220 мс). Больше — уже не игровые условия.
- Выделенный сервер не тестируется (виджеты создаются на сервере).
