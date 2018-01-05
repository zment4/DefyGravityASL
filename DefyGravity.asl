state("DefyGravity")
{
}

startup
{
	vars.gameScanTarget = new SigScanTarget(0, "10 3F ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 96 ?? ?? ?? 96 ?? ?? ?? 96");

	System.Threading.Thread.CurrentThread.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;

	timer.CurrentTimingMethod = TimingMethod.GameTime;
	
	vars.timerModel = new TimerModel { CurrentState = timer };
	vars.BaseTime = new TimeSpan();
}

init {
	vars.scannerTask = System.Threading.Tasks.Task.Run(() => {
		var ptr = IntPtr.Zero;
		
		while (ptr == IntPtr.Zero) {
			foreach (var page in game.MemoryPages(true)) {
				var scanner = new SignatureScanner(game, page.BaseAddress, (int) page.RegionSize);
				
				if (ptr == IntPtr.Zero) {
					ptr = scanner.Scan(vars.gameScanTarget);
				} else {
					break;
				}
			}
			
			if (ptr != IntPtr.Zero) {
				vars.levelTimer = new MemoryWatcher<float>(ptr + 0x1f4);
				vars.levelIndex = new MemoryWatcher<int>(ptr + 0x21c);
				
				vars.watchers = new MemoryWatcherList() {
					vars.levelTimer,
					vars.levelIndex
				};
			}
			
			System.Threading.Tasks.Task.Delay(100);
		}
	});
	
	vars.highestSplitTime = new TimeSpan();
}

update {
	if (!vars.scannerTask.IsCompleted) return;
	
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
	if (!vars.scannerTask.IsCompleted) return;
	
	var willStart = vars.levelIndex.Old == 0 && vars.levelIndex.Current == 1;
	
	if (willStart)
	{
		vars.BaseTime = new TimeSpan();
		vars.highestSplitTime = new TimeSpan();
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