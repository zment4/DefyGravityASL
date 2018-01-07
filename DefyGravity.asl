state("DefyGravity")
{
}

startup
{
	settings.Add("createui", false, "Create UI if needed");
	
	vars.gameScanTarget = new SigScanTarget(0, "10 3F ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 01 ?? ?? 01 01 00 00 00 00 40 4B 4C 00");

	System.Threading.Thread.CurrentThread.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;

	timer.CurrentTimingMethod = TimingMethod.GameTime;
	
	vars.timerModel = new TimerModel { CurrentState = timer };
	vars.BaseTime = new TimeSpan();
	
	vars.SetTextComponent = (Action<string, string, bool>)((id, text, create) => {
		var textSettings = timer.Layout.Components.Where(x => x.GetType().Name == "TextComponent").Select(x => x.GetType().GetProperty("Settings").GetValue(x, null));
		var textSetting = textSettings.FirstOrDefault(x => (x.GetType().GetProperty("Text1").GetValue(x, null) as string) == id);
		if (textSetting == null && create) 
		{
			var textComponentAssembly = Assembly.LoadFrom("Components\\LiveSplit.Text.dll");
			var textComponent = Activator.CreateInstance(textComponentAssembly.GetType("LiveSplit.UI.Components.TextComponent"), timer);
			timer.Layout.LayoutComponents.Add(new LiveSplit.UI.Components.LayoutComponent("LiveSplit.Text.dll", textComponent as LiveSplit.UI.Components.IComponent));
			
			textSetting = textComponent.GetType().GetProperty("Settings", BindingFlags.Instance | BindingFlags.Public).GetValue(textComponent, null);
			textSetting.GetType().GetProperty("Text1").SetValue(textSetting, id);
		}
		
		if (textSetting != null)
			textSetting.GetType().GetProperty("Text2").SetValue(textSetting, text);
	});	
}

init {
	vars.scannerTask = System.Threading.Tasks.Task.Run(async () => {
		var ptr = IntPtr.Zero;
		
		while (ptr == IntPtr.Zero) {
			foreach (var page in game.MemoryPages(true)) {
				var scanner = new SignatureScanner(game, page.BaseAddress, (int) page.RegionSize);
				
				if ((ptr = scanner.Scan(vars.gameScanTarget)) != IntPtr.Zero) 
					break;
			}
			
			if (ptr != IntPtr.Zero) {
				vars.levelTimer = new MemoryWatcher<float>(ptr + 0x1f4);
				vars.levelIndex = new MemoryWatcher<int>(ptr + 0x21c);
				var playerPtr = (ptr + 0x1d0 - modules.First().BaseAddress.ToInt32()).ToInt32();
				print(playerPtr.ToString("X8"));
				vars.playerDirection = new MemoryWatcher<int>(new DeepPointer(playerPtr, 0x10, 0x118));
				vars.playerIsAlive = new MemoryWatcher<bool>(new DeepPointer(playerPtr, 0x10, 0x15b));
				 
				vars.watchers = new MemoryWatcherList() {
					vars.levelTimer,
					vars.levelIndex,
					vars.playerDirection,
					vars.playerIsAlive
				};
				
			} else 
				await System.Threading.Tasks.Task.Delay(100);
		}
	});
	
	vars.playerDeathCount = 0;
	
	vars.highestSplitTime = new TimeSpan();
	
	vars.SetTextComponent("Death Count", vars.playerDeathCount.ToString(), settings["createui"]);
}

update {
	if (!vars.scannerTask.IsCompleted) return;
	
	vars.watchers.UpdateAll(game);
	
	if (settings.ResetEnabled && vars.levelIndex.Current == -1)
	{
		vars.playerDeathCount = 0;
		vars.timerModel.Reset();
	}

//	print("Loaded level: " + vars.levelIndex.Current.ToString() + " | Level timer: " + vars.levelTimer.Current.ToString("F1"));
	
	var currentLevelTimer = TimeSpan.FromSeconds(vars.levelTimer.Current);
	vars.highestSplitTime = vars.highestSplitTime < currentLevelTimer ? currentLevelTimer : vars.highestSplitTime;
	
	if (vars.playerIsAlive.Old == true && vars.playerIsAlive.Current == false)
		vars.playerDeathCount++;
		
	vars.SetTextComponent("Death Count", vars.playerDeathCount.ToString(), settings["createui"]);		
}

start {
	if (!vars.scannerTask.IsCompleted) return;
	
	var willStart = vars.levelIndex.Old == 0 && vars.levelIndex.Current == 1;
	
	if (willStart)
	{
		vars.BaseTime = new TimeSpan();
		vars.highestSplitTime = new TimeSpan();
		vars.playerDeathCount = 0;
	}
		
	return willStart;
}

split {
	if (!vars.scannerTask.IsCompleted) return;

	var willSplit = vars.levelIndex.Old != vars.levelIndex.Current && vars.levelIndex.Current != -1;
	
	if (willSplit)
	{
		vars.BaseTime += vars.highestSplitTime;
		vars.highestSplitTime = new TimeSpan();
	}
	
	return willSplit;
}

gameTime {
	if (!vars.scannerTask.IsCompleted) return;

	return vars.BaseTime + vars.highestSplitTime;
}

isLoading {
	if (!vars.scannerTask.IsCompleted) return;
	
	return vars.levelTimer.Old == vars.levelTimer.Current;
}

reset {
	return false;
}