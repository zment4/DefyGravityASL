state("DefyGravity")
{
}

startup
{
	vars.gameScanTarget = new SigScanTarget(0, "10 3F ?? 08 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 96");

	System.Threading.Thread.CurrentThread.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;

	timer.CurrentTimingMethod = TimingMethod.GameTime;
	
	vars.timerModel = new TimerModel { CurrentState = timer };
	vars.BaseTime = new TimeSpan();
}

init {
	var ptr = IntPtr.Zero;
	
	foreach (var page in game.MemoryPages(true)) {
		var scanner = new SignatureScanner(game, page.BaseAddress, (int) page.RegionSize);
		
		if (ptr == IntPtr.Zero) {
			ptr = scanner.Scan(vars.gameScanTarget);
		} else {
			break;
		}
	}
	
	if (ptr == IntPtr.Zero) {
		Thread.Sleep(1000);
		throw new Exception();
	}
	
	vars.levelTimer = new MemoryWatcher<float>(ptr + 0x1f4);
	vars.levelIndex = new MemoryWatcher<int>(ptr + 0x21c);
	
	vars.watchers = new MemoryWatcherList() {
		vars.levelTimer,
		vars.levelIndex
	};
	
	vars.highestSplitTime = new TimeSpan();
}

update {
	vars.watchers.UpdateAll(game);
	
	if (vars.levelIndex.Current == -1)
	{
		vars.timerModel.Reset();
	}

	print("Loaded level: " + vars.levelIndex.Current.ToString() + " | Level timer: " + vars.levelTimer.Current.ToString("F1"));
	
	var currentLevelTimer = TimeSpan.FromSeconds(vars.levelTimer.Current);
	vars.highestSplitTime = vars.highestSplitTime < currentLevelTimer ? currentLevelTimer : vars.highestSplitTime;
}

start {
	var willStart = vars.levelIndex.Old == 0 && vars.levelIndex.Current == 1;
	
	if (willStart)
	{
		vars.BaseTime = new TimeSpan();
		vars.highestSplitTime = new TimeSpan();
	}
		
	return willStart;
}

split {
	var willSplit = vars.levelIndex.Old != vars.levelIndex.Current && vars.levelIndex.Current != -1;
	
	if (willSplit)
	{
		vars.BaseTime += vars.highestSplitTime;
		vars.highestSplitTime = new TimeSpan();
	}
	
	return willSplit;
}

gameTime {
	return vars.BaseTime + vars.highestSplitTime;
}

isLoading {
	return vars.levelTimer.Old == vars.levelTimer.Current;
} 