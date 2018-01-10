state("DefyGravity")
{
	// Base pointers to heap
	int heapBase : "mscorwks.dll", 0x56799C;
	// mscorwks.dll+5679A0
}

startup
{
	settings.Add("createui", false, "Create UI if needed");
	settings.Add("disableonpractice", true, "Disable Autosplitter when in Practice Mode");
	settings.Add("forceigt", false, "Force current timing method to GameTime");
	settings.Add("debug", false, "Debug output");
//	settings.Add("twl", false, "GameTime is loadless instead of IGT");
	
	System.Threading.Thread.CurrentThread.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;
	
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
	var assemblyName = AssemblyName.GetAssemblyName(modules.First().FileName).Name;
	
	print(current.heapBase.ToString("X8"));
	vars.heapBasePointerAddres = 0x56799C;

	print("[DGASL] Assembly Name: " + assemblyName);
	print("[DGASL] Memory module size: " + modules.First().ModuleMemorySize.ToString("X8"));
	vars.exeVersion = "vanilla";
	if (modules.First().ModuleMemorySize == 0x58000)
		vars.exeVersion = "practiceMod1";
	if (assemblyName.Contains("PracticeMod") && modules.First().ModuleMemorySize == 0x5a000)
		vars.exeVersion = "practiceMod2";

	var add_offset = vars.exeVersion.Contains("practiceMod") ? 4 : 0;
		
	vars.gameScanTarget = new SigScanTarget(0, "10 3F ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 40 4B 4C 00");
	
	vars.watchers = new MemoryWatcherList();
	vars.initialized = false;
	vars.cancelRequested = false;
	
	vars.heapAddress = (IntPtr) 0;
	vars.scannerTask = System.Threading.Tasks.Task.Run(() => {
		var ptr = IntPtr.Zero;
		System.Threading.Tasks.Task.Delay(2000).Wait();
		
		while (ptr == IntPtr.Zero) {
			foreach (var page in game.MemoryPages(true)) {
				var scanner = new SignatureScanner(game, page.BaseAddress, (int) page.RegionSize);
				
				if ((ptr = scanner.Scan(vars.gameScanTarget)) != IntPtr.Zero) 
					break;
			}
			
			if (ptr != IntPtr.Zero) {
				// Sometimes the last three bytes are wrong (ie. they get moved right after scanning), but the correct address is consistent to calculate
				vars.heapAddress = ptr;
				print("[DGASL] Heap address: " + ptr.ToString("X8"));
				
				vars.levelIndex = new MemoryWatcher<int>(ptr + 0x21c + add_offset) { Name = "Level Index" };
				vars.hardMode = new MemoryWatcher<bool>(ptr + 0x22c + add_offset) { Name = "Hard Mode" };
				vars.levelTimer = new MemoryWatcher<float>(ptr + 0x1f4 + add_offset) { Name = "Level Timer" };
				var playerPtr = (ptr + 0x1d0 - modules.First().BaseAddress.ToInt32()).ToInt32();
				vars.playerDirection = new MemoryWatcher<int>(new DeepPointer(playerPtr, 0x10, 0x118)) { Name = "Player Direction" } ;
				vars.playerIsAlive = new MemoryWatcher<bool>(new DeepPointer(playerPtr, 0x10, 0x15b)) { Name = "Player Is Alive" } ;
						 
				vars.watchers = new MemoryWatcherList() {
					vars.levelTimer,
					vars.hardMode,
					vars.levelIndex,
					vars.playerDirection,
					vars.playerIsAlive
				};
				
				// Practice Mod
				if (vars.exeVersion.Contains("practiceMod")) {
					add_offset = vars.exeVersion.Contains("2") ? 8 : 0;
					
					var practicePtr = (ptr + 0x1e8 - modules.First().BaseAddress.ToInt32()).ToInt32();
					vars.practiceModeActive = new MemoryWatcher<int>(new DeepPointer(practicePtr, 0x0c + add_offset)) { Name = "Practice Mode Type" };
					
					vars.watchers.Add(vars.practiceModeActive);
				}
			} else 
				System.Threading.Tasks.Task.Delay(100).Wait();
				
			if (vars.cancelRequested)
				break;
		}
	});
	
	vars.playerDeathCount = 0;
	vars.lastLevelTime = 0f;
	
	vars.SetTextComponent("Death Count", vars.playerDeathCount.ToString(), settings["createui"]);
	vars.SetTextComponent("Last Level IGT", vars.lastLevelTime.ToString("F2"), settings["createui"]);
	
	vars.oldLastLevelTime = 0f;
	vars.highestSplitTime = 0f;
}

update {
	if (settings["debug"]) print((vars.scannerTask.IsCompleted ? "[DGASL] Scanning complete" : "[DGASL] Scanning for address"));
	
	if (!vars.scannerTask.IsCompleted) return false;
	vars.watchers.UpdateAll(game);
	if (!vars.initialized)
	{
		foreach (var w in vars.watchers)
		{
			w.Old = w.Current;
		}
		
		vars.initialized = true;
	}
	
	if (vars.levelIndex.Current == -1 && vars.levelIndex.Old != -1)
	{
		vars.playerDeathCount = 0;
		vars.lastLevelTime = 0f;
		vars.oldLastLevelTime = 0f;
		vars.highestSplitTime = 0f;
		
		if (settings.ResetEnabled)
		{
			print("[DGASL] Resetting due to entering main menu");
			vars.timerModel.Reset();
		}
	}

	if (vars.levelIndex.Current > 0 && timer.CurrentPhase == TimerPhase.Running && vars.highestSplitTime < vars.levelTimer.Current)
		vars.highestSplitTime = vars.levelTimer.Current;
		
	if (vars.playerIsAlive.Old == true && vars.playerIsAlive.Current == false)
		vars.playerDeathCount++;
		
	vars.SetTextComponent("Death Count", vars.playerDeathCount.ToString(), settings["createui"]);
	
	if (vars.levelTimer.Old > vars.levelTimer.Current)
		vars.lastLevelTime = vars.levelTimer.Old;
		
	if (vars.oldLastLevelTime != vars.lastLevelTime)
	{
		vars.SetTextComponent("Last Level IGT", vars.lastLevelTime.ToString("F2"), settings["createui"]);
	}
	
	if (settings["disableonpractice"] && vars.exeVersion.Contains("practiceMod") && vars.practiceModeActive.Current > 0 && timer.CurrentPhase != TimerPhase.NotRunning)
	{
		print("Practice mode detected, disabling");
		vars.timerModel.Reset();
		return false;
	}
	
	if (settings["debug"])
	{
		var str = "";
		foreach (var w in vars.watchers)
		{
			str += "[DGASL] " + w.Name + ": " + w.Current.ToString() + "\n";
		}
		
		str += "[DGASL] Found Heap Address: " + vars.heapAddress.ToString("X8") + "\n";
		
		str += "[DGASL] Heap Base: " + current.heapBase.ToString("X8");
		print(str);
	}
}

start { 
	if (!vars.initialized) return false;
	
	if (settings["forceigt"]) timer.CurrentTimingMethod = TimingMethod.GameTime;

	var willStart = vars.levelIndex.Old == 0 && vars.levelIndex.Current == 1;
	
	if (willStart)
	{
		vars.BaseTime = new TimeSpan();
		vars.playerDeathCount = 0;
		vars.lastLevelTime = 0f;
		vars.oldLastLevelTime = 0f;
		vars.highestSplitTime = 0f;
		
		vars.timerModel.Reset();
		print("[DGASL] Starting timer due to opening first level");
	}	
	
	return willStart;
}

split {
	if (!vars.initialized) return false;

	var willSplit = vars.levelIndex.Changed && vars.levelIndex.Current != -1 && !(vars.levelIndex.Current == 0 && vars.hardMode.Changed && vars.hardMode.Current);
	
	if (willSplit)
	{
		vars.BaseTime += TimeSpan.FromSeconds(vars.highestSplitTime);
		vars.highestSplitTime = 0f;
		print ("Splitting, level change from " + vars.levelIndex.Old + " to " + vars.levelIndex.Current);
	}
	
	return willSplit;
}

gameTime {
	if (!vars.initialized) return false;

	return vars.BaseTime + TimeSpan.FromSeconds(vars.highestSplitTime);
}

isLoading {
	if (!vars.initialized) return false;
	
	return vars.levelTimer.Old == vars.levelTimer.Current || vars.levelIndex.Current == 0;
}

reset {
	return false;
}

exit {
	vars.timerModel.Reset();
	vars.cancelRequested = true;
}

shutdown {
	vars.cancelRequested = true;
}