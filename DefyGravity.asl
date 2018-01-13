state("DefyGravity")
{
	// Base pointers to heap
//	int heapBase : "mscorwks.dll", 0x56799C;
	int heapBase : "mscorwks.dll", 0x5622AC;
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
	
	byte[] exeMD5HashBytes = new byte[0];
	
	using (var md5 = System.Security.Cryptography.MD5.Create())
	{
		using (var s = File.Open(modules.First().FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
		{
			exeMD5HashBytes = md5.ComputeHash(s);
		} 
	}
	
	var MD5Hash = exeMD5HashBytes.Select(x => x.ToString("X2")).Aggregate((a, b) => a + b);
	
	print(current.heapBase.ToString("X8"));

	print("[DGASL] Assembly Name: " + assemblyName);
	print("[DGASL] Module Name: " + modules.First().ModuleName);
	print("[DGASL] Memory Size: " + modules.Last().ModuleMemorySize.ToString("X8"));
	print("[DGASL] MD5: " + MD5Hash);

	vars.exeVersion = "Vanilla";
	var splitParts = assemblyName.Split('_');
	if (assemblyName.Contains("PracticeMod"))
	{
		vars.exeVersion = "PracticeMod_";
		vars.exeVersion += splitParts.Length > 2 ? splitParts[2] : "v4";
		var rev = splitParts.Where(x => x.StartsWith("r")).FirstOrDefault();
		vars.exeVersion += rev != null ? "_" + rev : "";
	}
	if (MD5Hash == "B347D51A915550A39242361282FD605E" || MD5Hash == "91D81CDD574E3BCF49ABCD733880C77C")
		vars.exeVersion = "PracticeMod_v1";
	if (MD5Hash == "4E094603360E281A11AFE6325A491C3B")
		vars.exeVersion = "PracticeMod_v2";
	if (MD5Hash == "E481DDBF5D4516683A54F7E23874DDDA")
		vars.exeVersion = "PracticeMod_v3";
		
	var gamePtrOffset = 0x0;
	var playerPtrOffset = 0x1d0;
	var practicePtrOffset = 0x1e8;
	var practiceDataOffset = 0x14;
	
	switch (vars.exeVersion as string)
	{
		case "PracticeMod_v1":
			gamePtrOffset = 0x4;
			practiceDataOffset = 0xc;
			break;
		case "PracticeMod_v2":
			gamePtrOffset = 0x4;
			practiceDataOffset = 0x14;
			break;
		case "PracticeMod_v3":
			gamePtrOffset = 0x4;
			practiceDataOffset = 0x14;
			break;
		case "PracticeMod_v4":
			gamePtrOffset = 0x4;
			practiceDataOffset = 0x14;
			break;
		case "PracticeMod_v5":
			gamePtrOffset = 0x10;
			playerPtrOffset = 0x1d8;
			practicePtrOffset = 0x1f0;
			practiceDataOffset = 0x14;
			break;
		case "PracticeMod_v6":
			gamePtrOffset = 0x10;
			playerPtrOffset = 0x1d8;
			practicePtrOffset = 0x1f0;
			practiceDataOffset = 0x2c;
			break;
		case "PracticeMod_v6_r2":
			gamePtrOffset = 0x14;
			playerPtrOffset = 0x1d8;
			practicePtrOffset = 0x1f0;
			practiceDataOffset = 0x30;
			break;
		case "PracticeMod_v6_r3":
			gamePtrOffset = 0x14;
			playerPtrOffset = 0x1d8;
			practicePtrOffset = 0x1f0;
			practiceDataOffset = 0x30;		
			break;		
		case "PracticeMod_v7":
			gamePtrOffset = 0x18;
			playerPtrOffset = 0x1d8;
			practicePtrOffset = 0x1f0;
			practiceDataOffset = 0x30;		
			break;		
	}
	
	print("[DGASL] Detected exe version: " + vars.exeVersion);
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
				if ((int) page.BaseAddress == current.heapBase) {
					print ("[DGASL] CurrentHeapBase: " + current.heapBase.ToString("X8") + " Base: " + page.BaseAddress.ToString("X8") + " Size: " + ((int) page.RegionSize).ToString("X8")); 
					var scanner = new SignatureScanner(game, page.BaseAddress, (int) page.RegionSize);
			
					ptr = scanner.Scan(vars.gameScanTarget);
					break;
				}
			}
			
			if (ptr != IntPtr.Zero) {
				// Sometimes the last three bytes are wrong (ie. they get moved right after scanning), but the correct address is consistent to calculate
				vars.heapAddress = ptr;
				print("[DGASL] Heap address: " + ptr.ToString("X8"));
				
				var gamePtr = ptr + gamePtrOffset;
				vars.levelIndex = new MemoryWatcher<int>(gamePtr + 0x21c) { Name = "Level Index" };
				vars.hardMode = new MemoryWatcher<bool>(gamePtr + 0x22c) { Name = "Hard Mode" };
				vars.levelTimer = new MemoryWatcher<float>(gamePtr + 0x1f4) { Name = "Level Timer" };
				
				var playerPtr = (ptr + playerPtrOffset - modules.First().BaseAddress.ToInt32()).ToInt32();
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
				if (vars.exeVersion.Contains("PracticeMod")) {
					var practicePtr = (ptr + practicePtrOffset - modules.First().BaseAddress.ToInt32()).ToInt32();
					vars.practiceModeActive = new MemoryWatcher<int>(new DeepPointer(practicePtr, practiceDataOffset)) { Name = "Practice Mode Type" };
					
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
		
	if (vars.playerIsAlive.Changed)
		vars.playerDeathCount++;
		
	vars.SetTextComponent("Death Count", vars.playerDeathCount.ToString(), settings["createui"]);
	
	if (vars.levelTimer.Old > vars.levelTimer.Current)
		vars.lastLevelTime = vars.levelTimer.Old;
		
	if (vars.oldLastLevelTime != vars.lastLevelTime)
	{
		vars.SetTextComponent("Last Level IGT", vars.lastLevelTime.ToString("F2"), settings["createui"]);
	}
	
	if (settings["disableonpractice"] && vars.exeVersion.Contains("PracticeMod") && vars.practiceModeActive.Current > 0 && timer.CurrentPhase != TimerPhase.NotRunning)
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
	
	if (timer.CurrentPhase == TimerPhase.Ended || timer.CurrentPhase == TimerPhase.NotRunning)
		vars.highestSplitTime = 0f;
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
	if (timer.CurrentPhase == TimerPhase.Running && vars.levelIndex.Old == 0 && !vars.hardMode.Changed) return false;
	
	var willSplit = vars.levelIndex.Changed && vars.levelIndex.Current != -1;
	
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
	vars.scannerTask = null;
}

shutdown {
	vars.cancelRequested = true;
}