state("DefyGravity")
{
	float levelTimer : "CSERHelper.dll", 0x0001D654, 0x430, 0x718, 0x66c, 0x1f4;
	int levelIndex : "CSERHelper.dll", 0x0001D654, 0x430, 0x718, 0x66c, 0x21c;
}

startup
{
	System.Threading.Thread.CurrentThread.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;

	timer.CurrentTimingMethod = TimingMethod.GameTime;
	
	vars.timerModel = new TimerModel { CurrentState = timer };
	vars.BaseTime = new TimeSpan();
}

start {
	var willStart = old.levelIndex == 0 && current.levelIndex == 1;
	
	if (willStart)
		vars.BaseTime = new TimeSpan();
		
	return willStart;
}

split {
	var willSplit = old.levelIndex != current.levelIndex;
	
	if (willSplit)
		vars.BaseTime += TimeSpan.FromSeconds(old.levelTimer);
	
	return willSplit;
}

gameTime {
	return vars.BaseTime + TimeSpan.FromSeconds(current.levelTimer);
}

isLoading {
	return current.levelTimer == old.levelTimer;
}

update {
	if (current.levelIndex == 0)
	{
		vars.timerModel.Reset();
	}
}