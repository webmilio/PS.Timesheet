using namespace System.Collections.Generic
using namespace System.Management.Automation.Host

#region Settings
$SettingsFile = "settings.json"
$script:Settings = [PSCustomObject]@{
    LogsDirectory = 'logs'
    ActivitiesDirectory = 'activities'
    
    TimeDisplayFormat = "HH:mm:ss"

    # It is recommended to leave this on an culture which uses a period (.) as a 
    # numeric separator since the online Excel uses periods as separators as well
    CultureName = "en-CA"
}

if (Test-Path -Path $SettingsFile)
{
    $script:Settings = Get-Content -Path $SettingsFile | ConvertFrom-Json
}

# We convert it back anyways in case we add new settings
$script:Settings | ConvertTo-Json | Set-Content -Path $SettingsFile

$Culture = [System.Globalization.CultureInfo]::GetCultureInfo($script:Settings.CultureName)

#endregion

#region Variables
#region Default choices
$breakChoice = [ChoiceDescription]::new("Brea&k", "Go on a break!")
$exitChoice = [ChoiceDescription]::new("&Exit", "End your timesheet")
#endregion

#region Choice bindings
$choiceBindings = [Dictionary[ChoiceDescription, System.Action]]::new()
$choiceBindings.Add($breakChoice, $function:TakeBreak)
$choiceBindings.Add($exitChoice, $function:End)
#endregion

#region Script
$script:labels = $null
$script:doing = $null
$script:doingIndex = $null

$script:startTime = $null
$script:running = $true

$script:log = $null
$script:logPath = $null
#endregion
#endregion

#region Choice Functions
function End { 
    EndSplit

    $script:running = $false 
}

function TakeBreak {
    Write-Host 'Taking a break!'

    EndSplit
}

function BeginSplit {
    $script:startTime = [datetime]::Now
    $logPath = GetLogPath -Time $script:startTime

    if ($logPath -ne $script:logPath) # Different split, reset log
    {
        for ($i = 0; $i -lt $script:log.Count; $i++) 
        {
            $script:log[$i] = [timespan]::Zero
        }
    }

    $script:logPath = $logPath
    Write-Host "Started working on $(GetDecisionName)"
}

function EndSplit {    
    if ($null -ne $script:doing)
    {
        $workTime = [datetime]::Now - $script:startTime

        $script:log[$script:doingIndex] += $workTime

        WriteSplit -Time $script:log[$script:doingIndex]
        Write-Host "Split ended for $(GetDecisionName) after $($workTime.Hours) hour(s), $($workTime.Minutes) minute(s)"
    }

    $script:startTime = $script:doing = $script:doingIndex = $null
}

function WriteSplit {    
    $hours = [string[]]::new($script:log.Length)

    for ($i = 0; $i -lt $script:log.Count; $i++) {
        $hours[$i] = [math]::Round($script:log[$i].TotalHours, 2).ToString($script:Culture)
    }

    ($hours -join [System.Environment]::NewLine) | Out-File -FilePath $script:logPath
}

function LoadLog {
    param($FilePath)
    $lines = Get-Content -Path $FilePath

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $script:log[$i] = [timespan]::FromHours([double]::Parse($lines[$i], $script:Culture))
    }
}

function GetDecisionName {
    return $script:labels[$script:doingIndex]
}

function GetLogPath {
    param($Time)
    return "$($script:Settings.LogsDirectory)\$($Time.ToString("ddMMyyyy")).txt"
}
#endregion

if (-Not (Test-Path $script:Settings.LogsDirectory))
{
    New-Item $script:Settings.LogsDirectory -ItemType Directory | Out-Null
    Write-Host "Created logs folder under '$($script:Settings.LogsDirectory)'."
}

if (-Not (Test-Path $script:Settings.ActivitiesDirectory))
{
    Write-Error "The '$activityFolder' was created and opened, please create your activity text files in the directory."

    New-Item $script:Settings.ActivitiesDirectory -ItemType Directory
    Invoke-Item $script:Settings.ActivitiesDirectory

    return
}

$activityFiles = Get-ChildItem -Path $script:Settings.ActivitiesDirectory -Filter "*.txt" | Sort-Object Name
$choices = [ChoiceDescription[]]::new($activityFiles.Count + 2)

$script:labels = [string[]]::new($choices.Length)
$script:log = [timespan[]]::new($choices.Length - $choiceBindings.Count) # Hopefully this doesn't cause problems later on

$choices[$choices.Length - 2] = $breakChoice
$choices[$choices.Length - 1] = $exitChoice

for ($i = 0; $i -lt $activityFiles.Length; $i++)
{
    $lines = Get-Content $activityFiles[$i]
    $choices[$i] = [ChoiceDescription]::new($lines[0], ($lines[1..($lines.Length - 1)] -join [System.Environment]::NewLine))
}

for ($i = 0; $i -lt $script:labels.Count; $i++) 
{
    $script:labels[$i] = $choices[$i].Label.Replace("&", [string]::Empty)
}

# Load existing log if it exists
$logPath = GetLogPath -Time $([datetime]::Now)
if (Test-Path $logPath)
{
    $script:logPath = $logPath

    LoadLog -FilePath $logPath
    Write-Host "Loaded existing log $logPath"
}

Write-Host "Starting timesheet at $([datetime]::Now.ToString($script:Settings.TimeDisplayFormat))"

do
{
    $decisionIndex = $Host.UI.PromptForChoice("Which activity are you doing?", $null, $choices, 0)
    $decision = $choices[$decisionIndex]

    if ($decision -eq $script:doing)
    {
        Write-Host "You're already working on $(GetDecisionName)"
    }
    else
    {
        $binding = $null

        if ($choiceBindings.TryGetValue($decision, [ref] $binding))
        {
            $binding.Invoke()
        }
        else
        {
            if ($null -ne $script:doing)
            {
                EndSplit
            }

            $script:doing = $decision
            $script:doingIndex = $decisionIndex

            BeginSplit
        }
    }
} 
while ($script:running)