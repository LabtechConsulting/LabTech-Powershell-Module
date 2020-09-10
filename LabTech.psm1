<#
.SYNOPSIS
    This is a PowerShell Module for LabTech.
    labtechconsulting.com
    labtechsoftware.com
    msdn.microsoft.com/powershell


.DESCRIPTION
    This is a set of commandlets to interface with the LabTech Agent.
    Tested Versions: v10.5, v11, v12, v2019

.NOTES
    Version:        1.9.0
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 1/23/2018
    Purpose/Change: Updates to address 32-bit vs. 64-bit environments

    Update Date: 2/1/2018
    Purpose/Change: Updates for support of Proxy Settings. Enabled -WhatIf processing for many functions.

    Update Date: 8/7/2018
    Purpose/Change: Added support for TLS 1.2

    Update Date: 8/28/2018
    Purpose/Change: Added Update-LTService function

    Update Date: 2/26/2019
    Purpose/Change: Update to support 32-bit execution in 64-bit OS without SYSNATIVE redirection

    Update Date: 9/9/2020
    Purpose/Change: Update to support 64-bit OS without SYSNATIVE redirection (ARM64)
#>

If (-not ($PSVersionTable)) {Write-Warning 'PS1 Detected. PowerShell Version 2.0 or higher is required.';return}
ElseIf ($PSVersionTable.PSVersion.Major -lt 3 ) {Write-Verbose 'PS2 Detected. PowerShell Version 3.0 or higher may be required for full functionality.'}

#Module Version
$ModuleVersion = "1.9.0"
$ModuleGuid='f1f06c84-00c8-11ea-b6e8-000c29aaa7df'

If ($env:PROCESSOR_ARCHITEW6432 -match '64' -and [IntPtr]::Size -ne 8) {
    Write-Warning '32-bit PowerShell session detected on 64-bit OS. Attempting to launch 64-Bit session to process commands.'
    $pshell="${env:windir}\SysNative\WindowsPowershell\v1.0\powershell.exe"
    If (!(Test-Path -Path $pshell) -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        Write-Debug 'SYSNATIVE PATH REDIRECTION IS NOT AVAILABLE. Attempting to disable System32 path redirection for native 64bit access.'
        $pshell="${env:windir}\System32\WindowsPowershell\v1.0\powershell.exe"

        If ($Null -eq ([System.Management.Automation.PSTypeName]'System.Win32').Type -or $Null -eq [system.win32].GetMethod('GetFinalPathName')) {
            Add-Type -Name Win32 -NameSpace System -UsingNamespace System.Text,Microsoft.Win32.SafeHandles,System.ComponentModel -Debug:$False -MemberDefinition @"
private const int CREATION_DISPOSITION_OPEN_EXISTING = 3;
private const int FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

[DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int GetFinalPathNameByHandle(IntPtr handle, [In, Out] StringBuilder path, int bufLen, int flags);

[DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(string lpFileName, int dwDesiredAccess, int dwShareMode,
    IntPtr SecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, IntPtr hTemplateFile);

    public static string GetFinalPathName(System.IO.DirectoryInfo targetpath)
    {
        SafeFileHandle directoryHandle = CreateFile(targetpath.FullName, 0, 2, System.IntPtr.Zero, CREATION_DISPOSITION_OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, System.IntPtr.Zero);
        if(directoryHandle.IsInvalid)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        StringBuilder path = new StringBuilder(512);
        int size = GetFinalPathNameByHandle(directoryHandle.DangerousGetHandle(), path, path.Capacity, 0);
        if (size<0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        // The remarks section of GetFinalPathNameByHandle mentions the return being prefixed with "\\?\"
        // More information about "\\?\" here -> http://msdn.microsoft.com/en-us/library/aa365247(v=VS.85).aspx
        string sPath = path.ToString();
        if( sPath.Length>8 && sPath.Substring(0,8) == @"\\?\UNC\" )
        {
            return @"\" + sPath.Substring(7);
        }
        else if( sPath.Length>4 && sPath.Substring(0,4) == @"\\?\" )
        {
            return sPath.Substring(4);
        }
        else
        {
            return sPath;
        }
    }
"@
        }#End If

        $System32Dir=Get-Item "${env:SystemRoot}\System32"
        $System32DirActual=[System.Win32]::GetFinalPathName($System32Dir)

        If (!($System32DirActual -eq $System32Dir.FullName)) {

            If ($Null -eq ([System.Management.Automation.PSTypeName]'Kernel32.Wow64').Type -or $Null -eq [Kernel32.Wow64].GetMethod('Wow64DisableWow64FsRedirection')) {
                Write-Debug 'Loading WOW64Redirection functions'

                Add-Type -Name Wow64 -Namespace Kernel32 -Debug:$False -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool Wow64DisableWow64FsRedirection(ref IntPtr ptr);

[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool Wow64RevertWow64FsRedirection(ref IntPtr ptr);
"@
            }

            Write-Verbose 'System32 path is redirected. Disabling redirection.'
            [ref]$ptr = New-Object System.IntPtr
            $Result = [Kernel32.Wow64]::Wow64DisableWow64FsRedirection($ptr)
            $System32DirActual=[System.Win32]::GetFinalPathName($System32Dir)
            If (!($System32DirActual -eq $System32Dir.FullName)) {
                $pshell=$Null
                Write-Warning 'Native 64-bit PowerShell environment unavailable. Execution will continue.'
            } ElseIf ($env:PROCESSOR_ARCHITEW6432 -match 'ARM64') {
                $pshell=$Null
                Write-Debug 'Native 64-bit PowerShell environment unavailable in ARM64. Execution will continue.'
            } Else {
                $FSRedirectionDisabled=$True
            }
        } Else {
            Write-Debug 'System32 path redirection to SysWOW64 is already disabled.'
        }#End If
    }#End If

    If ($pshell) {
        If ($myInvocation.Line) {
            &"$pshell" -NonInteractive -NoProfile $myInvocation.Line
        } Elseif ($myInvocation.InvocationName) {
            &"$pshell" -NonInteractive -NoProfile -File "$($myInvocation.InvocationName)" $args
        } Else {
            &"$pshell" -NonInteractive -NoProfile $myInvocation.MyCommand
        }#End If
        $ExitResult=$LASTEXITCODE

        If ($Null -ne ([System.Management.Automation.PSTypeName]'Kernel32.Wow64').Type -and $Null -ne [Kernel32.Wow64].GetMethod('Wow64DisableWow64FsRedirection') -and $FSRedirectionDisabled -eq $True) {
            [ref]$defaultptr = New-Object System.IntPtr
            $Result = [Kernel32.Wow64]::Wow64RevertWow64FsRedirection($defaultptr)
            Write-Verbose 'System32 path redirection has been re-enabled.'
        }#End If
        Write-Warning 'Exiting 64-bit session. Module will only remain loaded in native 64-bit PowerShell environment.'
        Exit $ExitResult
    }
}#End If

#Ignore SSL errors
If ($Null -eq ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
    Add-Type -Debug:$False @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#Enable TLS, TLS1.1, TLS1.2, TLS1.3 in this session if they are available
IF([Net.SecurityProtocolType]::Tls) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls}
IF([Net.SecurityProtocolType]::Tls11) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls11}
IF([Net.SecurityProtocolType]::Tls12) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12}
IF([Net.SecurityProtocolType]::Tls13) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13}

#region [Functions]-------------------------------------------------------------

Function Get-LTServiceInfo{
<#
.SYNOPSIS
    This function will pull all of the registry data into an object.

.NOTES
    Version:        1.5
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 8/24/2017
    Purpose/Change: Update to use Clear-Variable.

    Update Date: 3/12/2018
    Purpose/Change: Support for ShouldProcess to enable -Confirm and -WhatIf.

    Update Date: 8/28/2018
    Purpose/Change: Remove '~' from server addresses.

    Update Date: 1/19/2019
    Purpose/Change: Improved BasePath value assignment

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True, ConfirmImpact='Low')]
    Param ()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        Clear-Variable key,BasePath,exclude,Servers -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        $exclude = "PSParentPath","PSChildName","PSDrive","PSProvider","PSPath"
        $key = $Null
    }#End Begin

    Process{
        If ((Test-Path 'HKLM:\SOFTWARE\LabTech\Service') -eq $False){
            Write-Error "ERROR: Line $(LINENUM): Unable to find information on LTSvc. Make sure the agent is installed."
            Return $Null
        }#End If

        If ($PSCmdlet.ShouldProcess("LTService", "Retrieving Service Registry Values")) {
            Write-Verbose "Checking for LT Service registry keys."
            Try{
                $key = Get-ItemProperty 'HKLM:\SOFTWARE\LabTech\Service' -ErrorAction Stop | Select-Object * -exclude $exclude
                If ($Null -ne $key -and -not ($key|Get-Member -EA 0|Where-Object {$_.Name -match 'BasePath'})) {
                    If ((Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LTService') -eq $True) {
                        Try {
                            $BasePath = Get-Item $( Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LTService' -ErrorAction Stop|Select-Object -Expand ImagePath | Select-String -Pattern '^[^"][^ ]+|(?<=^")[^"]+'|Select-Object -Expand Matches -First 1 | Select-Object -Expand Value -EA 0 -First 1 ) | Select-Object -Expand DirectoryName -EA 0
                        } Catch {
                            $BasePath = "${env:windir}\LTSVC"
                        }#End Try
                    } Else {
                        $BasePath = "${env:windir}\LTSVC"
                    }#End If
                    Add-Member -InputObject $key -MemberType NoteProperty -Name BasePath -Value $BasePath
                }#End If
                $key.BasePath = [System.Environment]::ExpandEnvironmentVariables($($key|Select-Object -Expand BasePath -EA 0)) -replace '\\\\','\'
                If ($Null -ne $key -and ($key|Get-Member|Where-Object {$_.Name -match 'Server Address'})) {
                    $Servers = ($Key|Select-Object -Expand 'Server Address' -EA 0).Split('|')|ForEach-Object {$_.Trim() -replace '~',''}|Where-Object {$_ -match '.+'}
                    Add-Member -InputObject $key -MemberType NoteProperty -Name 'Server' -Value $Servers -Force
                }#End If
            }#End Try

            Catch{
                Write-Error "ERROR: Line $(LINENUM): There was a problem reading the registry keys. $($Error[0])"
            }#End Catch
        }#End If
    }#End Process

    End{
        If ($?){
            Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
            return $key
        } Else {
            Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
        }#End If
    }#End End
}#End Function Get-LTServiceInfo

Function Get-LTServiceSettings{
<#
.SYNOPSIS
    This function will pull the registry data from HKLM:\SOFTWARE\LabTech\Service\Settings into an object.

.NOTES
    Version:        1.1
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param ()

    Begin{
        Write-Verbose "Checking for registry keys."
        if ((Test-Path 'HKLM:\SOFTWARE\LabTech\Service\Settings') -eq $False){
            Write-Error "ERROR: Unable to find LTSvc settings. Make sure the agent is installed."
        }
        $exclude = "PSParentPath","PSChildName","PSDrive","PSProvider","PSPath"
    }#End Begin

    Process{
        Try{
            Get-ItemProperty HKLM:\SOFTWARE\LabTech\Service\Settings -ErrorAction Stop | Select-Object * -exclude $exclude
        }#End Try

        Catch{
            Write-Error "ERROR: There was a problem reading the registry keys. $($Error[0])"
        }#End Catch
    }#End Process

    End{
        if ($?){
            $key
        }
    }#End End
}#End Function Get-LTServiceSettings

Function Restart-LTService{
<#
.SYNOPSIS
    This function will restart the LabTech Services.

.NOTES
    Version:        1.3
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/13/2018
    Purpose/Change: Added additional debugging output, support for ShouldProcess (-Confirm, -WhatIf)

    Update Date: 3/21/2018
    Purpose/Change: Removed ErrorAction Override

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End Begin

    Process{
        if (-not (Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
            If ($WhatIfPreference -ne $True) {
                Write-Error "ERROR: Line $(LINENUM): Services NOT Found $($Error[0])"
                return
            } Else {
                Write-Error "What-If: Line $(LINENUM): Stopping: Services NOT Found"
                return
            }#End If
        }#End IF
        Try{
            Stop-LTService
        }#End Try
        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error stopping the services. $($Error[0])"
            return
        }#End Catch

        Try{
            Start-LTService
        }#End Try
        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error starting the services. $($Error[0])"
            return
        }#End Catch
    }#End Process

    End{
        If ($WhatIfPreference -ne $True) {
            If ($?) {Write-Output "Services Restarted successfully."}
            Else {$Error[0]}
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Restart-LTService

Function Stop-LTService{
<#
.SYNOPSIS
    This function will stop the LabTech Services.

.DESCRIPTION
    This function will verify that the LabTech services are present then attempt to stop them.
    It will then check for any remaining LabTech processes and kill them.

.NOTES
    Version:        1.3
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/12/2018
    Purpose/Change: Updated Support for ShouldProcess to enable -Confirm and -WhatIf parameters.

    Update Date: 3/21/2018
    Purpose/Change: Removed ErrorAction Override

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param()

    Begin{
        Clear-Variable sw,timeout,svcRun -EA 0 -WhatIf:$False -Confirm:$False -Verbose:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End Begin

    Process{
        if (-not (Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
            If ($WhatIfPreference -ne $True) {
                Write-Error "ERROR: Line $(LINENUM): Services NOT Found $($Error[0])"
                return
            } Else {
                Write-Error "What If: Line $(LINENUM): Stopping: Services NOT Found"
                return
            }#End If
        }#End If
        If ($PSCmdlet.ShouldProcess("LTService, LTSvcMon", "Stop-Service")) {
            $Null=Invoke-LTServiceCommand ('Kill VNC','Kill Trays') -EA 0 -WhatIf:$False -Confirm:$False
            Write-Verbose "Stopping Labtech Services"
            Try{
                ('LTService','LTSvcMon') | Foreach-Object {
                    Try {$Null=& "${env:windir}\system32\sc.exe" stop "$($_)" 2>''}
                    Catch {Write-Output "Error calling sc.exe."}
                }
                $timeout = new-timespan -Minutes 1
                $sw = [diagnostics.stopwatch]::StartNew()
                Write-Host -NoNewline "Waiting for Services to Stop."
                Do {
                    Write-Host -NoNewline '.'
                    Start-Sleep 2
                    $svcRun = ('LTService','LTSvcMon') | Get-Service -EA 0 | Where-Object {$_.Status -ne 'Stopped'} | Measure-Object | Select-Object -Expand Count
                } Until ($sw.elapsed -gt $timeout -or $svcRun -eq 0)
                Write-Host ""
                $sw.Stop()
                if ($svcRun -gt 0) {
                    Write-Verbose "Services did not stop. Terminating Processes after $(([int32]$sw.Elapsed.TotalSeconds).ToString()) seconds."
                }
                Get-Process | Where-Object {@('LTTray','LTSVC','LTSvcMon') -contains $_.ProcessName } | Stop-Process -Force -ErrorAction Stop -Whatif:$False -Confirm:$False
            }#End Try

            Catch{
                Write-Error "ERROR: Line $(LINENUM): There was an error stopping the LabTech processes. $($Error[0])"
                return
            }#End Catch
        }#End If
    }#End Process

    End{
        If ($WhatIfPreference -ne $True) {
            If ($?) {
                If((('LTService','LTSvcMon') | Get-Service -EA 0 | Where-Object {$_.Status -ne 'Stopped'} | Measure-Object | Select-Object -Expand Count) -eq 0){
                    Write-Output "Services Stopped successfully."
                } Else {
                    Write-Warning "WARNING: Line $(LINENUM): Services have not stopped completely."
                }
            } Else {$Error[0]}
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Stop-LTService

Function Start-LTService{
<#
.SYNOPSIS
    This function will start the LabTech Services.

.DESCRIPTION
    This function will verify that the LabTech services are present.
    It will then check for any process that is using the LTTray port (Default 42000) and kill it.
    Next it will start the services.

.NOTES
    Version:        1.5
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 5/11/2017
    Purpose/Change: added check for non standard port number and set services to auto start

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 12/14/2017
    Purpose/Change: Will increment the tray port if a conflict is detected.

    Update Date: 2/1/2018
    Purpose/Change: Added support for -WhatIf. Added Service Control Command to request agent check-in immediately after startup.

    Update Date: 3/21/2018
    Purpose/Change: Removed ErrorAction Override

    .LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        #Identify processes that are using the tray port
        [array]$processes = @()
        $Port = (Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand TrayPort -EA 0)
        if (-not ($Port)) {$Port = "42000"}
        $startedSvcCount=0
    }#End Begin

    Process{
        If (-not (Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
            If ($WhatIfPreference -ne $True) {
                Write-Error "ERROR: Line $(LINENUM): Services NOT Found $($Error[0])"
                return
            } Else {
                Write-Error "What If: Line $(LINENUM): Stopping: Services NOT Found"
                return
            }#End If
        }#End If
        Try{
            If((('LTService') | Get-Service -EA 0 | Where-Object {$_.Status -eq 'Stopped'} | Measure-Object | Select-Object -Expand Count) -gt 0) {
                Try {$netstat=& "${env:windir}\system32\netstat.exe" -a -o -n 2>'' | Select-String -Pattern " .*[0-9\.]+:$($Port).*[0-9\.]+:[0-9]+ .*?([0-9]+)" -EA 0}
                Catch {Write-Output "Error calling netstat.exe."; $netstat=$null}
                Foreach ($line in $netstat){
                    $processes += ($line -split ' {4,}')[-1]
                }#End Foreach
                $processes = $processes | Where-Object {$_ -gt 0 -and $_ -match '^\d+$'}| Sort-Object | Get-Unique
                If ($processes) {
                    Foreach ($proc in $processes){
                        Write-Output "Process ID:$proc is using port $Port. Killing process."
                        Try{Stop-Process -ID $proc -Force -Verbose -EA Stop}
                        Catch {
                            Write-Warning "WARNING: Line $(LINENUM): There was an issue killing the following process: $proc"
                            Write-Warning "WARNING: Line $(LINENUM): This generally means that a 'protected application' is using this port."
                            $newPort = [int]$port + 1
                            if($newPort -gt 42009) {$newPort = 42000}
                            Write-Warning "WARNING: Line $(LINENUM): Setting tray port to $newPort."
                            New-ItemProperty -Path "HKLM:\Software\Labtech\Service" -Name TrayPort -PropertyType String -Value $newPort -Force -WhatIf:$False -Confirm:$False | Out-Null
                        }#End Catch
                    }#End Foreach
                }#End If
            }#End If
            If ($PSCmdlet.ShouldProcess("LTService, LTSvcMon", "Start Service")) {
                @('LTService','LTSvcMon') | ForEach-Object {
                    If (Get-Service $_ -EA 0) {
                        Set-Service $_ -StartupType Automatic -EA 0 -Confirm:$False -WhatIf:$False
                        $Null=& "${env:windir}\system32\sc.exe" start "$($_)" 2>''
                        $startedSvcCount++
                        Write-Debug "Line $(LINENUM): Executed Start Service for $($_)"
                    }#End If
                }#End ForEach-Object
            }#End If
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error starting the LabTech services. $($Error[0])"
            return
        }#End Catch
    }#End Process

    End{
        If ($WhatIfPreference -ne $True) {
            If ($?){
                $svcnotRunning = ('LTService') | Get-Service -EA 0 | Where-Object {$_.Status -ne 'Running'} | Measure-Object | Select-Object -Expand Count
                If ($svcnotRunning -gt 0 -and $startedSvcCount -eq 2) {
                    $timeout = new-timespan -Minutes 1
                    $sw = [diagnostics.stopwatch]::StartNew()
                    Write-Host -NoNewline "Waiting for Services to Start."
                    Do {
                        Write-Host -NoNewline '.'
                        Start-Sleep 2
                        $svcnotRunning = ('LTService') | Get-Service -EA 0 | Where-Object {$_.Status -ne 'Running'} | Measure-Object | Select-Object -Expand Count
                    } Until ($sw.elapsed -gt $timeout -or $svcnotRunning -eq 0)
                    Write-Host ""
                    $sw.Stop()
                }#End If
                If ($svcnotRunning -eq 0) {
                    Write-Output "Services Started successfully."
                    $Null=Invoke-LTServiceCommand 'Send Status' -EA 0 -Confirm:$False
                } ElseIf ($startedSvcCount -gt 0) {
                    Write-Output "Service Start was issued but LTService has not reached Running state."
                } Else {
                    Write-Output "Service Start was not issued."
                }#End If
            }
            Else{
                $($Error[0])
            }#End If
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Start-LTService

Function Uninstall-LTService{
<#
.SYNOPSIS
    This function will uninstall the LabTech agent from the machine.

.DESCRIPTION
    This function will stop all the LabTech services. It will then download the current agent install MSI and issue an uninstall command.
    It will then download and run Agent_Uninstall.exe from the LabTech server. It will then scrub any remaining file/registry/service data.

.PARAMETER Server
    This is the URL to your LabTech server.
    Example: https://lt.domain.com
    This is used to download the uninstall utilities.
    If no server is provided the uninstaller will use Get-LTServiceInfo to get the server address.

.PARAMETER Backup
    This will run a 'New-LTServiceBackup' before uninstalling.

.PARAMETER Force
    This will force operation on an agent detected as a probe.

.EXAMPLE
    Uninstall-LTService
    This will uninstall the LabTech agent using the server address in the registry.

.EXAMPLE
    Uninstall-LTService -Server 'https://lt.domain.com'
    This will uninstall the LabTech agent using the provided server URL to download the uninstallers.

.NOTES
    Version:        1.9
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 6/10/2017
    Purpose/Change: Updates for pipeline input, support for multiple servers

    Update Date: 6/24/2017
    Purpose/Change: Update to detect Server Version and use updated URL format for LabTech 11 Patch 13.

    Update Date: 8/24/2017
    Purpose/Change: Update to use Clear-Variable. Modifications to Folder and Registry Delete steps. Additional Debugging.

    Update Date: 1/26/2017
    Purpose/Change: Added support for Proxy Server for Download and Installation steps.

    Update Date: 3/12/2018
    Purpose/Change: Added detection of "Probe" enabled agent.
    Added support for -Force parameter to override probe detection.
    Updated support of -WhatIf parameter.
    Added minimum size requirement for agent installer to detect and skip a bad file download.

    Update Date: 10/18/2018
    Purpose/Change: Added minimum size requirement for agent uninstaller exe to detect and skip a bad file download.
    Uninstall will proceed even if the agent uninstaller exe cannot be downloaded.

    Update Date: 1/21/2019
    Purpose/Change: Minor bugfixes/adjustments.
    Allow single label server name.

    Update Date: 2/28/2019
    Purpose/Change: Update to try both http and https method if not specified for Server

    Update Date: 6/22/2020
    Purpose/Change: Use unique pathname for Uninstall MSI, add Uninstaller EXE fallback

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [string[]]$Server,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]$Backup,
        [switch]$Force
    )

    Begin{
        Clear-Variable Executables,BasePath,reg,regs,installer,installerTest,installerResult,LTSI,uninstaller,uninstallerTest,uninstallerResult,xarg,Svr,SVer,SvrVer,SvrVerCheck,GoodServer,AlternateServer,Item -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

        If (-not ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()|Select-Object -Expand groups -EA 0) -match 'S-1-5-32-544'))) {
            Throw "Line $(LINENUM): Needs to be ran as Administrator"
        }

        $LTSI = Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
        If (($LTSI) -and ($LTSI|Select-Object -Expand Probe -EA 0) -eq '1') {
            If ($Force -eq $True) {
                Write-Output "Probe Agent Detected. UnInstall Forced."
            } Else {
                Write-Error -Exception [System.OperationCanceledException]"Line $(LINENUM): Probe Agent Detected. UnInstall Denied." -ErrorAction Stop
            }#End If
        }#End If

        If ($Backup){
            If ( $PSCmdlet.ShouldProcess("LTService","Backup Current Service Settings") ) {
                New-LTServiceBackup
            }#End If
        }#End If

        $BasePath = $(Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand BasePath -EA 0)
        If (-not ($BasePath)) {$BasePath = "${env:windir}\LTSVC"}
        $UninstallBase="${env:windir}\Temp"
        $UninstallEXE='Agent_Uninstall.exe'
        $UninstallMSI='RemoteAgent.msi'

        New-PSDrive HKU Registry HKEY_USERS -ErrorAction SilentlyContinue -WhatIf:$False -Confirm:$False -Debug:$False| Out-Null
        $regs = @( 'Registry::HKEY_LOCAL_MACHINE\Software\LabTechMSP',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\LabTech\Service',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\LabTech\LabVNC',
            'Registry::HKEY_LOCAL_MACHINE\Software\Wow6432Node\LabTech\Service',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Managed\\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\D1003A85576B76D45A1AF09A0FC87FAC\InstallProperties',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{3426921d-9ad5-4237-9145-f15dee7e3004}',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Appmgmt\{40bf8c82-ed0d-4f66-b73e-58a3d7ab6582}',
            'Registry::HKEY_CLASSES_ROOT\Installer\Dependencies\{3426921d-9ad5-4237-9145-f15dee7e3004}',
            'Registry::HKEY_CLASSES_ROOT\Installer\Dependencies\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}',
            'Registry::HKEY_CLASSES_ROOT\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
            'Registry::HKEY_CLASSES_ROOT\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{09DF1DCA-C076-498A-8370-AD6F878B6C6A}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{15DD3BF6-5A11-4407-8399-A19AC10C65D0}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{3C198C98-0E27-40E4-972C-FDC656EC30D7}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{459C65ED-AA9C-4CF1-9A24-7685505F919A}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{7BE3886B-0C12-4D87-AC0B-09A5CE4E6BD6}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{7E092B5C-795B-46BC-886A-DFFBBBC9A117}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{9D101D9C-18CC-4E78-8D78-389E48478FCA}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{B0B8CDD6-8AAA-4426-82E9-9455140124A1}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{B1B00A43-7A54-4A0F-B35D-B4334811FAA4}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{BBC521C8-2792-43FE-9C91-CCA7E8ACBCC9}',
            'Registry::HKEY_CLASSES_ROOT\CLSID\{C59A1D54-8CD7-4795-AEDD-F6F6E2DE1FE7}',
            'Registry::HKEY_CLASSES_ROOT\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
            'Registry::HKEY_CLASSES_ROOT\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\LabTech\Service',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\LabTech\LabVNC',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
            'HKU:\*\Software\Microsoft\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F'
        )

        $xarg = "/x ""$UninstallBase\$UninstallMSI"" /qn"
    }#End Begin

    Process{
        If (-not ($Server)){
            $Server = Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand 'Server' -EA 0
        }
        If (-not ($Server)){
            $Server = Read-Host -Prompt 'Provide the URL to your LabTech server (https://lt.domain.com)'
        }
        If (-not ($Server)){
            #Download $UninstallEXE
            $AlternateServer=$Null
            $uninstaller='https://s3.amazonaws.com/assets-cp/assets/Agent_Uninstall.exe'
            If ($PSCmdlet.ShouldProcess("$uninstaller", "DownloadFile")) {
                Write-Debug "Line $(LINENUM): Downloading $UninstallEXE from $uninstaller"
                $Script:LTServiceNetWebClient.DownloadFile($uninstaller,"$UninstallBase\$UninstallEXE")
                If ((Test-Path "$UninstallBase\$UninstallEXE")) {
                    If(((Get-Item "$UninstallBase\$UninstallEXE" -EA 0).length/1KB -gt 80)) {
                        $AlternateServer='https://s3.amazonaws.com'
                    } Else {
                        Write-Warning "Line $(LINENUM): $UninstallEXE size is below normal. Removing suspected corrupt file."
                        Remove-Item "$UninstallBase\$UninstallEXE" -ErrorAction SilentlyContinue -Force -Confirm:$False   
                    }#End If
                }#End If
            }#End If
        }
        $Server=ForEach ($Svr in $Server) {If (($Svr)) {If ($Svr -notmatch 'https?://.+') {"https://$($Svr)"}; $Svr}}
        ForEach ($Svr in $Server) {
            If (-not ($GoodServer)) {
                If ($Svr -match '^(https?://)?(([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}|[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*)$') {
                    Try{
                        If ($Svr -notmatch 'https?://.+') {$Svr = "http://$($Svr)"}
                        $SvrVerCheck = "$($Svr)/LabTech/Agent.aspx"
                        Write-Debug "Line $(LINENUM): Testing Server Response and Version: $SvrVerCheck"
                        $SvrVer = $Script:LTServiceNetWebClient.DownloadString($SvrVerCheck)

                        Write-Debug "Line $(LINENUM): Raw Response: $SvrVer"
                        $SVer = $SvrVer|select-string -pattern '(?<=[|]{6})[0-9]{1,3}\.[0-9]{1,3}'|ForEach-Object {$_.matches}|Select-Object -Expand value -EA 0
                        If ($Null -eq ($SVer)) {
                            Write-Verbose "Unable to test version response from $($Svr)."
                            Continue
                        }
                        $installer = "$($Svr)/LabTech/Service/LabTechRemoteAgent.msi"
                        $installerTest = [System.Net.WebRequest]::Create($installer)
                        If (($Script:LTProxy.Enabled) -eq $True) {
                            Write-Debug "Line $(LINENUM): Proxy Configuration Needed. Applying Proxy Settings to request."
                            $installerTest.Proxy=$Script:LTWebProxy
                        }#End If
                        $installerTest.KeepAlive=$False
                        $installerTest.ProtocolVersion = '1.0'
                        $installerResult = $installerTest.GetResponse()
                        $installerTest.Abort()
                        If ($installerResult.StatusCode -ne 200) {
                            Write-Warning "WARNING: Line $(LINENUM): Unable to download $UninstallMSI from server $($Svr)."
                            Continue
                        }
                        Else {
                            If ($PSCmdlet.ShouldProcess("$installer", "DownloadFile")) {
                                Write-Debug "Line $(LINENUM): Downloading $UninstallMSI from $installer"
                                $Script:LTServiceNetWebClient.DownloadFile($installer,"$UninstallBase\$UninstallMSI")
                                If ((Test-Path "$UninstallBase\$UninstallMSI")) {
                                    If (!((Get-Item "$UninstallBase\$UninstallMSI" -EA 0).length/1KB -gt 1234)) {
                                        Write-Warning "WARNING: Line $(LINENUM): $UninstallMSI size is below normal. Removing suspected corrupt file."
                                        Remove-Item "$UninstallBase\$UninstallMSI" -ErrorAction SilentlyContinue -Force -Confirm:$False
                                        Continue
                                    } Else {
                                        $AlternateServer = $Svr
                                    }#End If
                                }#End If
                            }#End If
                        }#End If

                        #Using $SVer results gathered above.
                        If ([System.Version]$SVer -ge [System.Version]'110.374') {
                            #New Style Download Link starting with LT11 Patch 13 - The Agent Uninstaller URI has changed.
                            $uninstaller = "$($Svr)/LabTech/Service/LabUninstall.exe"
                        } Else {
                            #Original Uninstaller URL
                            $uninstaller = "$($Svr)/LabTech/Service/LabUninstall.exe"
                        }
                        $uninstallerTest = [System.Net.WebRequest]::Create($uninstaller)
                        If (($Script:LTProxy.Enabled) -eq $True) {
                            Write-Debug "Line $(LINENUM): Proxy Configuration Needed. Applying Proxy Settings to request."
                            $uninstallerTest.Proxy=$Script:LTWebProxy
                        }#End If
                        $uninstallerTest.KeepAlive=$False
                        $uninstallerTest.ProtocolVersion = '1.0'
                        $uninstallerResult = $uninstallerTest.GetResponse()
                        $uninstallerTest.Abort()
                        If ($uninstallerResult.StatusCode -ne 200) {
                            Write-Warning "WARNING: Line $(LINENUM): Unable to download Agent_Uninstall from server."
                            Continue
                        } Else {
                            #Download $UninstallEXE
                            If ($PSCmdlet.ShouldProcess("$uninstaller", "DownloadFile")) {
                                Write-Debug "Line $(LINENUM): Downloading $UninstallEXE from $uninstaller"
                                $Script:LTServiceNetWebClient.DownloadFile($uninstaller,"$UninstallBase\$UninstallEXE")
                                If ((Test-Path "$UninstallBase\$UninstallEXE") -and !((Get-Item "$UninstallBase\$UninstallEXE" -EA 0).length/1KB -gt 80)) {
                                    Write-Warning "WARNING: Line $(LINENUM): $UninstallEXE size is below normal. Removing suspected corrupt file."
                                    Remove-Item "$UninstallBase\$UninstallEXE" -ErrorAction SilentlyContinue -Force -Confirm:$False
                                    Continue
                                }#End If
                            }#End If
                        }#End If
                        If ($WhatIfPreference -eq $True) {
                            $GoodServer = $Svr
                        } ElseIf ((Test-Path "$UninstallBase\$UninstallMSI") -and (Test-Path "$UninstallBase\$UninstallEXE")) {
                            $GoodServer = $Svr
                            Write-Verbose "Successfully downloaded files from $($Svr)."
                        } Else {
                            Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr). Uninstall file(s) could not be received."
                            Continue
                        }#End If
                    }#End Try
                    Catch {
                        Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr)."
                        Continue
                    }
                } ElseIf ($Svr) {
                    Write-Verbose "Server address $($Svr) is not formatted correctly. Example: https://lt.domain.com"
                }#End If
            } Else {
                Write-Debug "Line $(LINENUM): Server $($GoodServer) has been selected."
                Write-Verbose "Server has already been selected - Skipping $($Svr)."
            }#End If
        }#End Foreach
    }#End Process

    End{
        If ($GoodServer -match 'https?://.+' -or $AlternateServer -match 'https?://.+') {
            Try{
                Write-Output "Starting Uninstall."

                Try { Stop-LTService -ErrorAction SilentlyContinue } Catch {}

                #Kill all running processes from %ltsvcdir%
                If (Test-Path $BasePath){
                    $Executables = (Get-ChildItem $BasePath -Filter *.exe -Recurse -ErrorAction SilentlyContinue|Select-Object -Expand FullName)
                    If ($Executables) {
                        Write-Verbose "Terminating LabTech Processes from $($BasePath) if found running: $(($Executables) -replace [Regex]::Escape($BasePath),'' -replace '^\\','')"
                        Get-Process | Where-Object {$Executables -contains $_.Path } | ForEach-Object {
                            Write-Debug "Line $(LINENUM): Terminating Process $($_.ProcessName)"
                            $($_) | Stop-Process -Force -ErrorAction SilentlyContinue
                        }
                        Get-ChildItem $BasePath -Filter labvnc.exe -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction 0
                    }#End If

                    If ($PSCmdlet.ShouldProcess("$($BasePath)\wodVPN.dll", "Unregister DLL")) {
                        #Unregister DLL
                        Write-Debug "Line $(LINENUM): Executing Command ""regsvr32.exe /u $($BasePath)\wodVPN.dll /s"""
                        Try {& "${env:windir}\system32\regsvr32.exe" /u "$($BasePath)\wodVPN.dll" /s 2>''}
                        Catch {Write-Output "Error calling regsvr32.exe."}
                    }#End If
                }#End If

                If ($PSCmdlet.ShouldProcess("msiexec.exe $($xarg)", "Execute MSI Uninstall")) {
                    If ((Test-Path "$UninstallBase\$UninstallMSI")) {
                        #Run MSI uninstaller for current installation
                        Write-Verbose "Launching MSI Uninstall."
                        Write-Debug "Line $(LINENUM): Executing Command ""msiexec.exe $($xarg)"""
                        Start-Process -Wait -FilePath "${env:windir}\system32\msiexec.exe" -ArgumentList $xarg -WorkingDirectory $UninstallBase
                        Start-Sleep -Seconds 5
                    } Else {
                        Write-Verbose "WARNING: $UninstallBase\$UninstallMSI was not found."
                    }
                }#End If

                If ($PSCmdlet.ShouldProcess("$UninstallBase\$UninstallEXE", "Execute Agent Uninstall")) {
                    If ((Test-Path "$UninstallBase\$UninstallEXE")) {
                        #Run $UninstallEXE
                        Write-Verbose "Launching Agent Uninstaller"
                        Write-Debug "Line $(LINENUM): Executing Command ""$UninstallBase\$UninstallEXE"""
                        Start-Process -Wait -FilePath "$UninstallBase\$UninstallEXE" -WorkingDirectory $UninstallBase
                        Start-Sleep -Seconds 5
                    } Else {
                        Write-Verbose "WARNING: $UninstallBase\$UninstallEXE was not found."
                    }
                }#End If

                Write-Verbose "Removing Services if found."
                #Remove Services
                @('LTService','LTSvcMon','LabVNC') | ForEach-Object {
                    If (Get-Service $_ -EA 0) {
                        If ( $PSCmdlet.ShouldProcess("$($_)","Remove Service") ) {
                            Write-Debug "Line $(LINENUM): Removing Service: $($_)"
                            Try {& "${env:windir}\system32\sc.exe" delete "$($_)" 2>''}
                            Catch {Write-Output "Error calling sc.exe."}
                        }#End If
                    }#End If
                }#End ForEach-Object

                Write-Verbose "Cleaning Files remaining if found."
                #Remove %ltsvcdir% - Depth First Removal, First by purging files, then Removing Folders, to get as much removed as possible if complete removal fails
                @($BasePath, "${env:windir}\temp\_ltupdate", "${env:windir}\temp\_ltupdate") | foreach-object {
                    If ((Test-Path "$($_)" -EA 0)) {
                        If ( $PSCmdlet.ShouldProcess("$($_)","Remove Folder") ) {
                            Write-Debug "Line $(LINENUM): Removing Folder: $($_)"
                            Try {
                                Get-ChildItem -Path $_ -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.psiscontainer) } | foreach-object { Get-ChildItem -Path "$($_.FullName)" -EA 0 | Where-Object { -not ($_.psiscontainer) } | Remove-Item -Force -ErrorAction SilentlyContinue -Confirm:$False -WhatIf:$False }
                                Get-ChildItem -Path $_ -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.psiscontainer) } | Sort-Object { $_.fullname.length } -Descending | Remove-Item -Force -ErrorAction SilentlyContinue -Recurse -Confirm:$False -WhatIf:$False
                                Remove-Item -Recurse -Force -Path $_ -ErrorAction SilentlyContinue -Confirm:$False -WhatIf:$False
                            } Catch {}
                        }#End If
                    }#End If
                }#End Foreach-Object

                Write-Verbose "Cleaning Registry Keys if found."
                #Remove all registry keys - Depth First Value Removal, then Key Removal, to get as much removed as possible if complete removal fails
                Foreach ($reg in $regs) {
                    If ((Test-Path "$($reg)" -EA 0)) {
                        Write-Debug "Line $(LINENUM): Found Registry Key: $($reg)"
                        If ( $PSCmdlet.ShouldProcess("$($Reg)","Remove Registry Key") ) {
                            Try {
                                Get-ChildItem -Path $reg -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.name.length } -Descending | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$False -WhatIf:$False
                                Remove-Item -Recurse -Force -Path $reg -ErrorAction SilentlyContinue -Confirm:$False -WhatIf:$False
                            } Catch {}
                        }#End If
                    }#End If
                }#End Foreach
            }#End Try

            Catch{
                Write-Error "ERROR: Line $(LINENUM): There was an error during the uninstall process. $($Error[0])" -ErrorAction Stop
            }#End Catch

            If ($WhatIfPreference -ne $True) {
                If ($?){
                    #Post Uninstall Check
                    If((Test-Path "${env:windir}\ltsvc") -or (Test-Path "${env:windir}\temp\_ltupdate") -or (Test-Path registry::HKLM\Software\LabTech\Service) -or (Test-Path registry::HKLM\Software\WOW6432Node\Labtech\Service)){
                        Start-Sleep -Seconds 10
                    }#End If
                    If((Test-Path "${env:windir}\ltsvc") -or (Test-Path "${env:windir}\temp\_ltupdate") -or (Test-Path registry::HKLM\Software\LabTech\Service) -or (Test-Path registry::HKLM\Software\WOW6432Node\Labtech\Service)){
                        Write-Error "ERROR: Line $(LINENUM): Remnants of previous install still detected after uninstall attempt. Please reboot and try again."
                    } Else {
                        Write-Output "LabTech has been successfully uninstalled."
                    }#End If
                } Else {
                    $($Error[0])
                }#End If
            }#End If
        } ElseIf ($WhatIfPreference -ne $True) {
            Write-Error "ERROR: Line $(LINENUM): No valid server was reached to use for the uninstall." -ErrorAction Stop
        }#End If

        If ($WhatIfPreference -ne $True) {
            #Cleanup uninstall files
            Remove-Item "$UninstallBase\$UninstallEXE","$UninstallBase\$UninstallMSI" -ErrorAction SilentlyContinue -Force -Confirm:$False
        }#End If

        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Uninstall-LTService

Function Install-LTService{
<#
.SYNOPSIS
    This function will install the LabTech agent on the machine.

.DESCRIPTION
    This function will install the LabTech agent on the machine with the specified server/password/location.

.PARAMETER Server
    This is the URL to your LabTech server.
    example: https://lt.domain.com
    This is used to download the installation files.
    (Get-LTServiceInfo|Select-Object -Expand 'Server Address' -ErrorAction SilentlyContinue)

.PARAMETER ServerPassword
    This is the server password that agents use to authenticate with the LabTech server.
    SELECT SystemPassword FROM config;

.PARAMETER InstallerToken
    Permits use of installer tokens for customized MSI downloads. (Other installer types are not supported)

.PARAMETER LocationID
    This is the LocationID of the location that the agent will be put into.
    (Get-LTServiceInfo).LocationID

.PARAMETER TrayPort
    This is the port LTSvc.exe listens on for communication with LTTray processes.

.PARAMETER Rename
    This will call Rename-LTAddRemove after the install.

.PARAMETER Hide
    This will call Hide-LTAddRemove after the install.

.PARAMETER SkipDotNet
    This will disable the error checking for the .NET 3.5 and .NET 2.0 frameworks during the install process.

.PARAMETER Force
    This will disable some of the error checking on the install process.

.PARAMETER NoWait
    This will skip the ending health check for the install process.
    The function will exit once the installer has completed.

.EXAMPLE
    Install-LTService -Server https://lt.domain.com -Password 'plain text pass' -LocationID 42
    This will install the LabTech agent using the provided Server URL, Password, and LocationID.

.NOTES
    Version:        2.1
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 6/10/2017
    Purpose/Change: Updates for pipeline input, support for multiple servers

    Update Date: 6/24/2017
    Purpose/Change: Update to detect Server Version and use updated URL format for LabTech 11 Patch 13.

    Update Date: 8/24/2017
    Purpose/Change: Update to use Clear-Variable. Additional Debugging.

    Update Date: 8/29/2017
    Purpose/Change: Additional Debugging.

    Update Date: 9/7/2017
    Purpose/Change: Support for ShouldProcess to enable -Confirm and -WhatIf.

    Update Date: 1/26/2018
    Purpose/Change: Added support for Proxy Server for Download and Installation steps.

    Update Date: 2/13/2018
    Purpose/Change: Added -TrayPort parameter.

    Update Date: 3/13/2018
    Purpose/Change: Added -NoWait parameter.
    Added minimum size requirement for agent installer to detect and skip a bad file download.

    Update Date: 6/5/2018
    Purpose/Change: Added -SkipDotNet parameter.
    Allows for skipping of .NET 3.5 and 2.0 framework checks for installing on OS with .NET 4.0+ already installed

    Update Date: 1/21/2019
    Purpose/Change: Minor bugfixes/adjustments.
    Allow single label server name, accept Agent ID 1 as valid.

    Update Date: 2/28/2019
    Purpose/Change: Update to try both http and https methods if not specified for Server

    Update Date: 12/28/2019
    Purpose/Change: Handle .NET 3.5 in pending state, accept .NET 4.0+ or higher with -Force parameter

    Update Date: 6/10/2020
    Purpose/Change: Remove Deployment.aspx dependance

    Update Date: 6/11/2020
    Purpose/Change: Update to work with or without Deployment.aspx

    Update Date: 6/20/2020
    Purpose/Change: Added -InstallerToken parameter. Added Installer cleanup.
    Allows for MSI download and installation without -ServerPassword parameter
    Remove unprotected references to the Server Password

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True,DefaultParameterSetName = 'deployment')]
    Param(
        [Parameter(ParameterSetName = 'deployment')]
        [Parameter(ParameterSetName = 'installertoken')]
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory=$True)]
        [string[]]$Server,
        [Parameter(ParameterSetName = 'deployment')]
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [Alias("Password")]
        [string]$ServerPassword,
        [Parameter(ParameterSetName = 'installertoken')]
        [ValidatePattern('(?s:^[0-9a-z]+$)')]
        [string]$InstallerToken,
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [int]$LocationID,
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [int]$TrayPort,
        [Parameter()]
        [AllowNull()]
        [string]$Rename,
        [switch]$Hide,
        [switch]$SkipDotNet,
        [switch]$Force,
        [switch]$NoWait
    )

    Begin{
        Clear-Variable DotNET,OSVersion,PasswordArg,Result,logpath,logfile,curlog,installer,installerTest,installerResult,GoodServer,GoodTrayPort,TestTrayPort,Svr,SVer,SvrVer,SvrVerCheck,iarg,timeout,sw,tmpLTSI -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

        If (!($Force)) {
            If (Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue) {
                If ($WhatIfPreference -ne $True) {
                    Write-Error "ERROR: Line $(LINENUM): Services are already installed." -ErrorAction Stop
                } Else {
                    Write-Error "ERROR: Line $(LINENUM): What if: Stopping: Services are already installed." -ErrorAction Stop
                }#End If
            }#End If
        }#End If

        If (-not ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()|Select-Object -Expand groups -EA 0) -match 'S-1-5-32-544'))) {
            Throw "Needs to be ran as Administrator"
        }

        If (!$SkipDotNet){
            $DotNET = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -recurse -EA 0 | Get-ItemProperty -name Version,Release -EA 0 | Where-Object { $_.PSChildName -match '^(?!S)\p{L}'} | Select-Object -ExpandProperty Version -EA 0
            If (-not ($DotNet -like '3.5.*')){
                Write-Output ".NET Framework 3.5 installation needed."
                #Install-WindowsFeature Net-Framework-Core
                $OSVersion = [System.Environment]::OSVersion.Version

                If ([version]$OSVersion -gt [version]'6.2'){
                    Try{
                        If ( $PSCmdlet.ShouldProcess('NetFx3', 'Enable-WindowsOptionalFeature') ) {
                            $Install = Get-WindowsOptionalFeature -Online -FeatureName 'NetFx3'
                            If (!($Install.State -eq 'EnablePending')) {
                                $Install = Enable-WindowsOptionalFeature -Online -FeatureName 'NetFx3' -All -NoRestart
                            }
                            If ($Install.RestartNeeded -or $Install.State -eq 'EnablePending') {
                                Write-Output ".NET Framework 3.5 installed but a reboot is needed."
                            }
                        }
                    }
                    Catch{
                        Write-Error "ERROR: Line $(LINENUM): .NET 3.5 install failed." -ErrorAction Continue
                        If (!($Force)) { Write-Error ("Line $(LINENUM):",$Install) -ErrorAction Stop }
                    }
                }
                ElseIf ([version]$OSVersion -gt [version]'6.1'){
                    If ( $PSCmdlet.ShouldProcess("NetFx3", "Add Windows Feature") ) {
                        Try {$Result=& "${env:windir}\system32\Dism.exe" /English /NoRestart /Online /Enable-Feature /FeatureName:NetFx3 2>''}
                        Catch {Write-Output "Error calling Dism.exe."; $Result=$Null}
                        Try {$Result=& "${env:windir}\system32\Dism.exe" /English /Online /Get-FeatureInfo /FeatureName:NetFx3 2>''}
                        Catch {Write-Output "Error calling Dism.exe."; $Result=$Null}
                        If ($Result -contains 'State : Enabled'){
                            Write-Warning "WARNING: Line $(LINENUM): .Net Framework 3.5 has been installed and enabled."
                        } ElseIf ($Result -contains 'State : Enable Pending'){
                            Write-Warning "WARNING: Line $(LINENUM): .Net Framework 3.5 installed but a reboot is needed."
                        } Else {
                            Write-Error "ERROR: Line $(LINENUM): .NET Framework 3.5 install failed." -ErrorAction Continue
                            If (!($Force)) { Write-Error ("ERROR: Line $(LINENUM):",$Result) -ErrorAction Stop }
                        }#End If
                    }#End If
                }#End If

                $DotNET = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -recurse | Get-ItemProperty -name Version -EA 0 | Where-Object{ $_.PSChildName -match '^(?!S)\p{L}'} | Select-Object -ExpandProperty Version
            }#End If

            If (-not ($DotNet -like '3.5.*')){
                If (($Force)) {
                    If ($DotNet -match '(?m)^[2-4].\d'){
                        Write-Error "ERROR: Line $(LINENUM): .NET 3.5 is not detected and could not be installed." -ErrorAction Continue
                    } Else {
                        Write-Error "ERROR: Line $(LINENUM): .NET 2.0 or greater is not detected and could not be installed." -ErrorAction Stop
                    }#End If
                } Else {
                    Write-Error "ERROR: Line $(LINENUM): .NET 3.5 is not detected and could not be installed." -ErrorAction Stop
                }#End If
            }#End If
        }#End If

        $InstallBase="${env:windir}\Temp\LabTech"
        $InstallMSI='Agent_Install.msi'
        $logfile = "LTAgentInstall"
        $curlog = "$($InstallBase)\$($logfile).log"
        If (-not (Test-Path -PathType Container -Path "$InstallBase\Installer" )){
            New-Item "$InstallBase\Installer" -type directory -ErrorAction SilentlyContinue | Out-Null
        }#End if
        If ((Test-Path -PathType Leaf -Path $($curlog))){
            If ($PSCmdlet.ShouldProcess("$($curlog)","Rotate existing log file")){
                Get-Item -LiteralPath $curlog -EA 0 | Where-Object {$_} | Foreach-Object {
                    Rename-Item -Path $($_|Select-Object -Expand FullName -EA 0) -NewName "$($logfile)-$(Get-Date $($_|Select-Object -Expand LastWriteTime -EA 0) -Format 'yyyyMMddHHmmss').log" -Force -Confirm:$False -WhatIf:$False
                    Remove-Item -Path $($_|Select-Object -Expand FullName -EA 0) -Force -EA 0 -Confirm:$False -WhatIf:$False
                }#End Foreach-Object
            }#End If
        }#End If
    }#End Begin

    Process{
        If (-not ($LocationID -or $PSCmdlet.ParameterSetName -eq 'installertoken')){
            $LocationID = "1"
        }
        If (-not ($TrayPort) -or -not ($TrayPort -ge 1 -and $TrayPort -le 65535)){
            $TrayPort = "42000"
        }
        $Server=ForEach ($Svr in $Server) {If ($Svr -notmatch 'https?://.+') {"https://$($Svr)"}; $Svr}
        ForEach ($Svr in $Server) {
            If (-not ($GoodServer)) {
                If ($Svr -match '^(https?://)?(([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}|[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*)$') {
                    If ($Svr -notmatch 'https?://.+') {$Svr = "http://$($Svr)"}
                    Try {
                        If ($PSCmdlet.ParameterSetName -eq 'installertoken') {
                            Write-Debug "Line $(LINENUM): Skipping Server Version Check. Using Installer Token for download."
                            $installer = "$($Svr)/LabTech/Deployment.aspx?InstallerToken=$InstallerToken"
                        } Else {
                            $SvrVerCheck = "$($Svr)/LabTech/Agent.aspx"
                            Write-Debug "Line $(LINENUM): Testing Server Response and Version: $SvrVerCheck"
                            $SvrVer = $Script:LTServiceNetWebClient.DownloadString($SvrVerCheck)
                            Write-Debug "Line $(LINENUM): Raw Response: $SvrVer"
                            $SVer = $SvrVer|select-string -pattern '(?<=[|]{6})[0-9]{1,3}\.[0-9]{1,3}'|ForEach-Object {$_.matches}|Select-Object -Expand value -EA 0
                            If ($Null -eq $SVer) {
                                Write-Verbose "Unable to test version response from $($Svr)."
                                Continue
                            }
                            If ([System.Version]$SVer -ge [System.Version]'110.374') {
                                #New Style Download Link starting with LT11 Patch 13 - Direct Location Targeting is no longer available
                                $installer = "$($Svr)/LabTech/Deployment.aspx?Probe=1&installType=msi&MSILocations=1"
                            } Else {
                                #Original URL
                                Write-Warning 'Update your damn server!'
                                $installer = "$($Svr)/LabTech/Deployment.aspx?Probe=1&installType=msi&MSILocations=$LocationID"
                            }

                            # Vuln test June 10, 2020: ConnectWise Automate API Vulnerability - Only test if version is below known minimum.
                            Try{
                                If ([System.Version]$SVer -lt [System.Version]'200.197') { 
                                    $HTTP_Request = [System.Net.WebRequest]::Create("$($Svr)/LabTech/Deployment.aspx")
                                    If ($HTTP_Request.GetResponse().StatusCode -eq 'OK') {
                                        $Message = @('Your server is vulnerable!!')
                                        $Message += 'https://docs.connectwise.com/ConnectWise_Automate/ConnectWise_Automate_Supportability_Statements/Supportability_Statement%3A_ConnectWise_Automate_Mitigation_Steps'
                                        Write-Warning $($Message | Out-String)
                                    }
                                }
                            }
                            Catch {
                                If (!$ServerPassword) {
                                    Write-Error 'ServerPassword needed.'
                                    Break
                                }
                            }
                            If ($ServerPassword) { $installer = "$($Svr)/LabTech/Service/LabTechRemoteAgent.msi" }
                        }#End If

                        If ( $PSCmdlet.ShouldProcess($installer, "DownloadFile") ) {
                            Write-Debug "Line $(LINENUM): Downloading $InstallMSI from $installer"
                            $Script:LTServiceNetWebClient.DownloadFile($installer,"$InstallBase\Installer\$InstallMSI")
                            If((Test-Path "$InstallBase\Installer\$InstallMSI") -and  !((Get-Item "$InstallBase\Installer\$InstallMSI" -EA 0).length/1KB -gt 1234)) {
                                Write-Warning "WARNING: Line $(LINENUM): $InstallMSI size is below normal. Removing suspected corrupt file."
                                Remove-Item "$InstallBase\Installer\$InstallMSI" -ErrorAction SilentlyContinue -Force -Confirm:$False
                                Continue
                            }#End If
                        }#End If

                        If ($WhatIfPreference -eq $True) {
                            $GoodServer = $Svr
                        } ElseIf (Test-Path "$InstallBase\Installer\$InstallMSI") {
                            $GoodServer = $Svr
                            Write-Verbose "$InstallMSI downloaded successfully from server $($Svr)."
                        } Else {
                            Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr). No installation file was received."
                            Continue
                        }#End If
                    }#End Try
                    Catch {
                        Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr)."
                        Continue
                    }
                } Else {
                    Write-Warning "WARNING: Line $(LINENUM): Server address $($Svr) is not formatted correctly. Example: https://lt.domain.com"
                }
            } Else {
                Write-Debug "Line $(LINENUM): Server $($GoodServer) has been selected."
                Write-Verbose "Server has already been selected - Skipping $($Svr)."
            }
        }#End Foreach
    }#End Process

    End{
        If ($GoodServer) {

            If ( $WhatIfPreference -eq $True -and (Get-PSCallStack)[1].Command -eq 'Redo-LTService' ) {
                Write-Debug "Line $(LINENUM): Skipping Preinstall Check: Called by Redo-LTService and ""-WhatIf=`$True"""
            } Else {
                If ((Test-Path "${env:windir}\ltsvc" -EA 0) -or (Test-Path "${env:windir}\temp\_ltupdate" -EA 0) -or (Test-Path registry::HKLM\Software\LabTech\Service -EA 0) -or (Test-Path registry::HKLM\Software\WOW6432Node\Labtech\Service -EA 0)){
                    Write-Warning "WARNING: Line $(LINENUM): Previous installation detected. Calling Uninstall-LTService"
                    Uninstall-LTService -Server $GoodServer -Force
                    Start-Sleep 10
                }#End If
            }#End If

            If ($WhatIfPreference -ne $True) {
                $GoodTrayPort=$Null;
                $TestTrayPort=$TrayPort;
                For ($i=0; $i -le 10; $i++) {
                    If (-not ($GoodTrayPort)) {
                        If (-not (Test-LTPorts -TrayPort $TestTrayPort -Quiet)){
                            $TestTrayPort++;
                            If ($TestTrayPort -gt 42009) {$TestTrayPort=42000}
                        } Else {
                            $GoodTrayPort=$TestTrayPort
                        }#End If
                    }#End If
                }#End For
                If ($GoodTrayPort -and $GoodTrayPort -ne $TrayPort -and $GoodTrayPort -ge 1 -and $GoodTrayPort -le 65535) {
                    Write-Verbose "TrayPort $($TrayPort) is in use. Changing TrayPort to $($GoodTrayPort)"
                    $TrayPort=$GoodTrayPort
                }#End If
                Write-Output "Starting Install."
            }#End If

            #Build parameter string
            $iarg =(@(
                "/i `"$InstallBase\Installer\$InstallMSI`"",
                "SERVERADDRESS=$GoodServer",
                $(If ($ServerPassword -and $ServerPassword -match '.') {"SERVERPASS=""$ServerPassword"""} Else {""}),
                $(If ($LocationID -and $LocationID -match '^\d+$') {"LOCATION=$LocationID"} Else {""}),
                $(If ($TrayPort -and $TrayPort -ne 42000) {"SERVICEPORT=$TrayPort"} Else {""}),
                "/qn",
                "/l ""$InstallBase\$logfile.log""") | Where-Object {$_}) -join ' '

            Try{
                If ( $PSCmdlet.ShouldProcess("msiexec.exe $($iarg)", "Execute Install") ) {
                    $InstallAttempt=0
                    Do {
                        If ($InstallAttempt -gt 0 ) {
                            Write-Warning "WARNING: Line $(LINENUM): Service Failed to Install. Retrying in 30 seconds." -WarningAction 'Continue'
                            $timeout = new-timespan -Seconds 30
                            $sw = [diagnostics.stopwatch]::StartNew()
                            Do {
                                Start-Sleep 5
                                $svcRun = ('LTService') | Get-Service -EA 0 | Measure-Object | Select-Object -Expand Count
                            } Until ($sw.elapsed -gt $timeout -or $svcRun -eq 1)
                            $sw.Stop()
                        }#End If
                        $InstallAttempt++
                        $svcRun = ('LTService') | Get-Service -EA 0 | Measure-Object | Select-Object -Expand Count
                        If ($svcRun -eq 0) {
                            Write-Verbose "Launching Installation Process: msiexec.exe $(($iarg -join ''))"
                            Start-Process -Wait -FilePath "${env:windir}\system32\msiexec.exe" -ArgumentList $iarg -WorkingDirectory $env:TEMP
                            Start-Sleep 5
                        }
                        $svcRun = ('LTService') | Get-Service -EA 0 | Measure-Object | Select-Object -Expand Count
                    } Until ($InstallAttempt -ge 3 -or $svcRun -eq 1)
                    If ($svcRun -eq 0) {
                        Write-Error "ERROR: Line $(LINENUM): LTService was not installed. Installation failed."
                        Return
                    }
                }#End If
                If (($Script:LTProxy.Enabled) -eq $True) {
                    Write-Verbose "Proxy Configuration Needed. Applying Proxy Settings to Agent Installation."
                    If ( $PSCmdlet.ShouldProcess($Script:LTProxy.ProxyServerURL, "Configure Agent Proxy") ) {
                        $svcRun = ('LTService') | Get-Service -EA 0 | Where-Object {$_.Status -eq 'Running'} | Measure-Object | Select-Object -Expand Count
                        If ($svcRun -ne 0) {
                            $timeout = new-timespan -Minutes 2
                            $sw = [diagnostics.stopwatch]::StartNew()
                            Write-Host -NoNewline "Waiting for Service to Start."
                            Do {
                                Write-Host -NoNewline '.'
                                Start-Sleep 2
                                $svcRun = ('LTService') | Get-Service -EA 0 | Where-Object {$_.Status -eq 'Running'} | Measure-Object | Select-Object -Expand Count
                            } Until ($sw.elapsed -gt $timeout -or $svcRun -eq 1)
                            Write-Host ""
                            $sw.Stop()
                            If ($svcRun -eq 1) {
                                Write-Debug "Line $(LINENUM): LTService Initial Startup Successful."
                            } Else {
                                Write-Debug "Line $(LINENUM): LTService Initial Startup failed to complete within expected period."
                            }#End If
                        }#End If
                        Set-LTProxy -ProxyServerURL $Script:LTProxy.ProxyServerURL -ProxyUsername $Script:LTProxy.ProxyUsername -ProxyPassword $Script:LTProxy.ProxyPassword -Confirm:$False -WhatIf:$False
                    }#End If
                } Else {
                    Write-Verbose "No Proxy Configuration has been specified - Continuing."
                }#End If
                If (!($NoWait) -and $PSCmdlet.ShouldProcess("LTService","Monitor For Successful Agent Registration") ) {
                    $timeout = new-timespan -Minutes 3
                    $sw = [diagnostics.stopwatch]::StartNew()
                    Write-Host -NoNewline "Waiting for agent to register."
                    Do {
                        Write-Host -NoNewline '.'
                        Start-Sleep 5
                        $tmpLTSI = (Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand 'ID' -EA 0)
                    } Until ($sw.elapsed -gt $timeout -or $tmpLTSI -ge 1)
                    Write-Host ""
                    $sw.Stop()
                    Write-Verbose "Completed wait for LabTech Installation after $(([int32]$sw.Elapsed.TotalSeconds).ToString()) seconds."
                    $Null=Get-LTProxy -ErrorAction Continue
                }#End If
                If ($Hide) {Hide-LTAddRemove}
            }#End Try

            Catch{
                Write-Error "ERROR: Line $(LINENUM): There was an error during the install process. $($Error[0])"
                Return
            }#End Catch

            If ($WhatIfPreference -ne $True) {
                #Cleanup Install files
                Remove-Item "$InstallBase\Installer\$InstallMSI" -ErrorAction SilentlyContinue -Force -Confirm:$False
                @($curlog,"${env:windir}\LTSvc\Install.log") | Foreach-Object {
                    If ((Test-Path -PathType Leaf -LiteralPath $($_))) {
                        $logcontents=Get-Content -Path $_
                        $logcontents=$logcontents -replace '(?<=PreInstallPass:[^\r\n]+? (?:result|value)): [^\r\n]+',': <REDACTED>'
                        If ($logcontents) {Set-Content -Path $_ -Value $logcontents -Force -Confirm:$False}
                    }#End If
                }#End Foreach-Object

                $tmpLTSI = Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
                If (($tmpLTSI)) {
                    If (($tmpLTSI|Select-Object -Expand 'ID' -EA 0) -ge 1) {
                        Write-Output "LabTech has been installed successfully. Agent ID: $($tmpLTSI|Select-Object -Expand 'ID' -EA 0) LocationID: $($tmpLTSI|Select-Object -Expand 'LocationID' -EA 0)"
                    } ElseIf (!($NoWait)) {
                        Write-Error "ERROR: Line $(LINENUM): LabTech installation completed but Agent failed to register within expected period." -ErrorAction Continue
                    } Else {
                        Write-Warning "WARNING: Line $(LINENUM): LabTech installation completed but Agent did not yet register." -WarningAction Continue
                    }#End If
                } Else {
                    If (($Error)) {
                        Write-Error "ERROR: Line $(LINENUM): There was an error installing LabTech. Check the log, $InstallBase\$logfile.log $($Error[0])"
                        Return
                    } ElseIf (!($NoWait)) {
                        Write-Error "ERROR: Line $(LINENUM): There was an error installing LabTech. Check the log, $InstallBase\$logfile.log"
                        Return
                    } Else {
                        Write-Warning "WARNING: Line $(LINENUM): LabTech installation may not have succeeded." -WarningAction Continue
                    }#End If
                }#End If
            }#End If
            If (($Rename) -and $Rename -notmatch 'False'){ Rename-LTAddRemove -Name $Rename }
        } ElseIf ( $WhatIfPreference -ne $True ) {
            Write-Error "ERROR: Line $(LINENUM): No valid server was reached to use for the install."
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Install-LTService

Function Redo-LTService{
<#
.SYNOPSIS
    This function will reinstall the LabTech agent from the machine.

.DESCRIPTION
    This script will attempt to pull all current settings from machine and issue an 'Uninstall-LTService', 'Install-LTService' with gathered information.
    If the function is unable to find the settings it will ask for needed parameters.

.PARAMETER Server
    This is the URL to your LabTech server.
    Example: https://lt.domain.com
    This is used to download the installation and removal utilities.
    If no server is provided the uninstaller will use Get-LTServiceInfo to get the server address.
    If it is unable to find LT currently installed it will try Get-LTServiceInfoBackup

.PARAMETER ServerPassword
    This is the Server Password to your LabTech server.
    SELECT SystemPassword FROM config;

.PARAMETER InstallerToken
    Permits use of installer tokens for customized MSI downloads. (Other installer types are not supported)

.PARAMETER LocationID
    The LocationID of the location that you want the agent in
    example: 555

.PARAMETER Backup
    This will run a New-LTServiceBackup command before uninstalling.

.PARAMETER Hide
    Will remove from add-remove programs

.PARAMETER Rename
    This will call Rename-LTAddRemove to rename the install in Add/Remove Programs

.PARAMETER SkipDotNet
    This will disable the error checking for the .NET 3.5 and .NET 2.0 frameworks during the install process.

.PARAMETER Force
    This will force operation on an agent detected as a probe.

.EXAMPLE
    Redo-LTService
    This will ReInstall the LabTech agent using the server address in the registry.

.EXAMPLE
    Redo-LTService -Server https://lt.domain.com -Password sQWZzEDYKFFnTT0yP56vgA== -LocationID 42
    This will ReInstall the LabTech agent using the provided server URL to download the installation files.

.NOTES
    Version:        1.6
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 6/8/2017
    Purpose/Change: Update to support user provided settings for -Server, -Password, -LocationID.

    Update Date: 6/10/2017
    Purpose/Change: Updates for pipeline input, support for multiple servers

    Update Date: 8/24/2017
    Purpose/Change: Update to use Clear-Variable.

    Update Date: 3/12/2018
    Purpose/Change: Added detection of "Probe" enabled agent.
    Added support for -Force parameter to override probe detection.
    Updated support of -WhatIf parameter.

    Update Date: 2/22/2019
    Purpose/Change: Added -SkipDotNet parameter.
    Allows for skipping of .NET 3.5 and 2.0 framework checks for installing on OS with .NET 4.0+ already installed

    Update Date: 6/20/2020
    Purpose/Change: Added -InstallerToken parameter.
    Allows for MSI download and installation without -ServerPassword parameter

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True,DefaultParameterSetName = 'deployment')]
    Param(
        [Parameter(ParameterSetName = 'deployment')]
        [Parameter(ParameterSetName = 'installertoken')]
        [Parameter(ValueFromPipelineByPropertyName = $True, ValueFromPipeline=$True)]
        [AllowNull()]
        [string[]]$Server,
        [Parameter(ParameterSetName = 'deployment')]
        [Parameter(ValueFromPipelineByPropertyName = $True, ValueFromPipeline=$True)]
        [Alias("Password")]
        [string]$ServerPassword,
        [Parameter(ParameterSetName = 'installertoken')]
        [ValidatePattern('(?s:^[0-9a-z]+$)')]
        [string]$InstallerToken,
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [string]$LocationID,
        [switch]$Backup,
        [switch]$Hide,
        [Parameter()]
        [AllowNull()]
        [string]$Rename,
        [switch]$SkipDotNet,
        [switch]$Force
    )

    Begin{
        Clear-Variable PasswordArg, RenameArg, Svr, ServerList, Settings -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

        # Gather install stats from registry or backed up settings
        Try {
            $Settings = Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False
            If ($Null -ne $Settings) {
                If (($Settings|Select-Object -Expand Probe -EA 0) -eq '1') {
                    If ($Force -eq $True) {
                        Write-Output "Probe Agent Detected. Re-Install Forced."
                    } Else {
                        If ($WhatIfPreference -ne $True) {
                            Write-Error -Exception [System.OperationCanceledException]"ERROR: Line $(LINENUM): Probe Agent Detected. Re-Install Denied." -ErrorAction Stop
                        } Else {
                            Write-Error -Exception [System.OperationCanceledException]"What If: Line $(LINENUM): Probe Agent Detected. Re-Install Denied." -ErrorAction Stop
                        }#End If
                    }#End If
                }#End If
            }#End If
        } Catch {
            Write-Debug "Line $(LINENUM): Failed to retrieve current Agent Settings."
        }#End Catch
        If ($Null -eq $Settings) {
            Write-Debug "Line $(LINENUM): Unable to retrieve current Agent Settings. Testing for Backup Settings"
            Try {
                $Settings = Get-LTServiceInfoBackup -EA 0
            } Catch {}
        }
        $ServerList=@()
    }#End Begin

    Process{
        if (-not ($Server)){
            if ($Settings){
                $Server = $Settings|Select-Object -Expand 'Server' -EA 0
            }
            if (-not ($Server)){
                $Server = Read-Host -Prompt 'Provide the URL to your LabTech server (https://lt.domain.com):'
            }
        }
        if (-not ($LocationID)){
            if ($Settings){
                $LocationID = $Settings|Select-Object -Expand LocationID -EA 0
            }
            if (-not ($LocationID)){
                $LocationID = Read-Host -Prompt 'Provide the LocationID'
            }
        }
        if (-not ($LocationID)){
            $LocationID = "1"
        }
        $ServerList += $Server
    }#End Process

    End{
        If ($Backup){
            If ( $PSCmdlet.ShouldProcess("LTService","Backup Current Service Settings") ) {
                New-LTServiceBackup
            }#End If
        }#End If

        $RenameArg=''
        If ($Rename){
            $RenameArg = "-Rename $Rename"
        }

        If ($PSCmdlet.ParameterSetName -eq 'installertoken') {
            $PasswordPresent = "-InstallerToken 'REDACTED'"
        } ElseIf (($ServerPassword)){
            $PasswordPresent = "-Password 'REDACTED'"
        }

        Write-Output "Reinstalling LabTech with the following information, -Server $($ServerList -join ',') $PasswordPresent -LocationID $LocationID $RenameArg"
        Write-Verbose "Starting: Uninstall-LTService -Server $($ServerList -join ',')"
        Try{
            Uninstall-LTService -Server $ServerList -ErrorAction Stop -Force
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error during the reinstall process while uninstalling. $($Error[0])" -ErrorAction Stop
        }#End Catch

        Finally{
            If ($WhatIfPreference -ne $True) {
                Write-Verbose "Waiting 20 seconds for prior uninstall to settle before starting Install."
                Start-Sleep 20
            }
        }

        Write-Verbose "Starting: Install-LTService -Server $($ServerList -join ',') $PasswordPresent -LocationID $LocationID -Hide:`$$($Hide) $RenameArg"
        Try{
            If ($PSCmdlet.ParameterSetName -ne 'installertoken') {
                Install-LTService -Server $ServerList -ServerPassword $ServerPassword -LocationID $LocationID -Hide:$Hide -Rename $Rename -SkipDotNet:$SkipDotNet -Force
            } Else {
                Install-LTService -Server $ServerList -InstallerToken $InstallerToken -LocationID $LocationID -Hide:$Hide -Rename $Rename -SkipDotNet:$SkipDotNet -Force
            }
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error during the reinstall process while installing. $($Error[0])" -ErrorAction Stop
        }#End Catch

        If (!($?)){
            $($Error[0])
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Redo-LTService
Set-Alias -Name ReInstall-LTService -Value Redo-LTService

Function Update-LTService{
<#
.SYNOPSIS
    This function will manually update the LabTech agent to the requested version.

.DESCRIPTION
    This script will attempt to pull current server settings from machine, then download and run the agent updater.


.PARAMETER Version
    This is the agent version to install.
    Example: 120.240
    This is needed to download the update file. If omitted, the version advertised by the server will be used.

.EXAMPLE
    Update-LTService -Version 120.240
    This will update the Automate agent to the specific version requested, using the server address in the registry.

.EXAMPLE
    Update-LTService
    This will update the Automate agent to the current version advertised, using the server address in the registry.

.NOTES
    Version:        1.1
    Author:         Darren White
    Creation Date:  8/28/2018
    Purpose/Change: Initial function development

    Update Date: 1/21/2019
    Purpose/Change: Minor bugfixes/adjustments.
    Allow single label server name, accept less digits for Agent Minor version number

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [parameter(Position=0)]
        [AllowNull()]
        [string]$Version
    )

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        Clear-Variable Svr, GoodServer, Settings -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        $Settings = Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False
        $updaterPath = [System.Environment]::ExpandEnvironmentVariables("%windir%\temp\_LTUpdate")
        $xarg=@("/o""$updaterPath""","/y")
        $uarg=@("""$updaterPath\Update.ini""")
    }#End Begin

    Process{
        if (-not ($Server)){
            If ($Settings){
                $Server = $Settings|Select-Object -Expand 'Server' -EA 0
            }
        }

        $Server=ForEach ($Svr in $Server) {If ($Svr -notmatch 'https?://.+') {"https://$($Svr)"}; $Svr}
        Foreach ($Svr in $Server) {
            If (-not ($GoodServer)) {
                If ($Svr -match '^(https?://)?(([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}|[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*)$') {
                    If ($Svr -notmatch 'https?://.+') {$Svr = "http://$($Svr)"}
                    Try {
                        $SvrVerCheck = "$($Svr)/LabTech/Agent.aspx"
                        Write-Debug "Line $(LINENUM): Testing Server Response and Version: $SvrVerCheck"
                        $SvrVer = $Script:LTServiceNetWebClient.DownloadString($SvrVerCheck)
                        Write-Debug "Line $(LINENUM): Raw Response: $SvrVer"
                        $SVer = $SvrVer|select-string -pattern '(?<=[|]{6})[0-9]{1,3}\.[0-9]{1,3}'|ForEach-Object {$_.matches}|Select-Object -Expand value -EA 0
                        If ($Null -eq ($SVer)) {
                            Write-Verbose "Unable to test version response from $($Svr)."
                            Continue
                        }
                        If ($Version -match '[1-9][0-9]{2}\.[0-9]{1,3}') {
                            $updater = "$($Svr)/LabTech/Updates/LabtechUpdate_$($Version).zip"
                        } ElseIf ([System.Version]$SVer -ge [System.Version]'105.001') {
                            $Version = $SVer
                            Write-Verbose "Using detected version ($Version) from server: $($Svr)."
                            $updater = "$($Svr)/LabTech/Updates/LabtechUpdate_$($Version).zip"
                        }

                        #Kill all running processes from $updaterPath
                        if (Test-Path $updaterPath){
                            $Executables = (Get-ChildItem $updaterPath -Filter *.exe -Recurse -ErrorAction SilentlyContinue|Select-Object -Expand FullName)
                            if ($Executables) {
                                Write-Verbose "Terminating LabTech Processes from $($updaterPath) if found running: $(($Executables) -replace [Regex]::Escape($updaterPath),'' -replace '^\\','')"
                                Get-Process | Where-Object {$Executables -contains $_.Path } | ForEach-Object {
                                    Write-Debug "Line $(LINENUM): Terminating Process $($_.ProcessName)"
                                    $($_) | Stop-Process -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }#End If

                        #Remove $updaterPath - Depth First Removal, First by purging files, then Removing Folders, to get as much removed as possible if complete removal fails
                        @("$updaterPath") | foreach-object {
                            If ((Test-Path "$($_)" -EA 0)) {
                                If ( $PSCmdlet.ShouldProcess("$($_)","Remove Folder") ) {
                                    Write-Debug "Line $(LINENUM): Removing Folder: $($_)"
                                    Try {
                                        Get-ChildItem -Path $_ -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.psiscontainer) } | foreach-object { Get-ChildItem -Path "$($_.FullName)" -EA 0 | Where-Object { -not ($_.psiscontainer) } | Remove-Item -Force -ErrorAction SilentlyContinue -Confirm:$False -WhatIf:$False }
                                        Get-ChildItem -Path $_ -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.psiscontainer) } | Sort-Object { $_.fullname.length } -Descending | Remove-Item -Force -ErrorAction SilentlyContinue -Recurse -Confirm:$False -WhatIf:$False
                                        Remove-Item -Recurse -Force -Path $_ -ErrorAction SilentlyContinue -Confirm:$False -WhatIf:$False
                                    } Catch {}
                                }#End If
                            }#End If
                        }#End Foreach-Object

                        Try {
                            If (-not (Test-Path -PathType Container -Path "$updaterPath" )){
                                New-Item "$updaterPath" -type directory -ErrorAction SilentlyContinue | Out-Null
                            }#End if
                            $updaterTest = [System.Net.WebRequest]::Create($updater)
                            If (($Script:LTProxy.Enabled) -eq $True) {
                                Write-Debug "Line $(LINENUM): Proxy Configuration Needed. Applying Proxy Settings to request."
                                $updaterTest.Proxy=$Script:LTWebProxy
                            }#End If
                            $updaterTest.KeepAlive=$False
                            $updaterTest.ProtocolVersion = '1.0'
                            $updaterResult = $updaterTest.GetResponse()
                            $updaterTest.Abort()
                            If ($updaterResult.StatusCode -ne 200) {
                                Write-Warning "WARNING: Line $(LINENUM): Unable to download LabtechUpdate.exe version $Version from server $($Svr)."
                                Continue
                            } Else {
                                If ( $PSCmdlet.ShouldProcess($updater, "DownloadFile") ) {
                                    Write-Debug "Line $(LINENUM): Downloading LabtechUpdate.exe from $updater"
                                    $Script:LTServiceNetWebClient.DownloadFile($updater,"$updaterPath\LabtechUpdate.exe")
                                    If((Test-Path "$updaterPath\LabtechUpdate.exe") -and  !((Get-Item "$updaterPath\LabtechUpdate.exe" -EA 0).length/1KB -gt 1234)) {
                                        Write-Warning "WARNING: Line $(LINENUM): LabtechUpdate.exe size is below normal. Removing suspected corrupt file."
                                        Remove-Item "$updaterPath\LabtechUpdate.exe" -ErrorAction SilentlyContinue -Force -Confirm:$False
                                        Continue
                                    }#End If
                                }#End If

                                If ($WhatIfPreference -eq $True) {
                                    $GoodServer = $Svr
                                } ElseIf (Test-Path "$updaterPath\LabtechUpdate.exe") {
                                    $GoodServer = $Svr
                                    Write-Verbose "LabtechUpdate.exe downloaded successfully from server $($Svr)."
                                } Else {
                                    Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr). No update file was received."
                                    Continue
                                }#End If
                            }#End If
                        }#End Try
                        Catch {
                            Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading $updater."
                            Continue
                        }
                    }#End Try
                    Catch {
                        Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr)."
                        Continue
                    }
                } Else {
                    Write-Warning "WARNING: Line $(LINENUM): Server address $($Svr) is not formatted correctly. Example: https://lt.domain.com"
                }
            } Else {
                Write-Debug "Line $(LINENUM): Server $($GoodServer) has been selected."
                Write-Verbose "Server has already been selected - Skipping $($Svr)."
            }
        }#End Foreach
    }#End Process

    End{
        $detectedVersion = $Settings|Select-Object -Expand 'Version' -EA 0
        If ($Null -eq $detectedVersion){
            Write-Error "ERROR: Line $(LINENUM): No existing installation was found." -ErrorAction Stop
            Return
        }
        If ([System.Version]$detectedVersion -ge [System.Version]$Version) {
            Write-Warning "WARNING: Line $(LINENUM): Installed version detected ($detectedVersion) is higher than or equal to the requested version ($Version)."
            Return
        }
        If (-not ($GoodServer)) {
            Write-Warning "WARNING: Line $(LINENUM): No valid server was detected."
            Return
        }
        If ([System.Version]$SVer -gt [System.Version]$Version) {
            Write-Warning "WARNING: Line $(LINENUM): Server version detected ($SVer) is higher than the requested version ($Version)."
            Return
        }

        Try{
            Stop-LTService
        }#End Try
        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error stopping the services. $($Error[0])"
            Return
        }#End Catch

        Write-Output "Updating Agent with the following information: Server $($GoodServer), Version $Version"
        Try{
            If ($PSCmdlet.ShouldProcess("LabtechUpdate.exe $($xarg)", "Extracting update files")) {
                If ((Test-Path "$updaterPath\LabtechUpdate.exe")) {
                    #Extract Update Files
                    Write-Verbose "Launching LabtechUpdate Self-Extractor."
                    Write-Debug "Line $(LINENUM): Executing Command ""LabtechUpdate.exe $($xarg)"""
                    Try {
                        Push-Location $updaterPath
                        & "$updaterPath\LabtechUpdate.exe" $($xarg) 2>''
                        Pop-Location
                    }
                    Catch {Write-Output "Error calling LabtechUpdate.exe."}
                    Start-Sleep -Seconds 5
                } Else {
                    Write-Verbose "WARNING: $updaterPath\LabtechUpdate.exe was not found."
                }
            }#End If

            If ($PSCmdlet.ShouldProcess("Update.exe $($uarg)", "Launching Updater")) {
                If ((Test-Path "$updaterPath\Update.exe")) {
                    #Extract Update Files
                    Write-Verbose "Launching Labtech Updater"
                    Write-Debug "Line $(LINENUM): Executing Command ""Update.exe $($uarg)"""
                    Try {& "$updaterPath\Update.exe" $($uarg) 2>''}
                    Catch {Write-Output "Error calling Update.exe."}
                    Start-Sleep -Seconds 5
                } Else {
                    Write-Verbose "WARNING: $updaterPath\Update.exe was not found."
                }
            }#End If

        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error during the update process $($Error[0])" -ErrorAction Continue
        }#End Catch

        Try{
            Start-LTService
        }#End Try
        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error starting the services. $($Error[0])"
            Return
        }#End Catch

        If ($WhatIfPreference -ne $True) {
            If ($?) {}
            Else {$Error[0]}
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Update-LTService

Function Get-LTErrors{
<#
.SYNOPSIS
    This will pull the %ltsvcdir%\LTErrors.txt file into an object.

.EXAMPLE
    Get-LTErrors | where {(Get-date $_.Time) -gt (get-date).AddHours(-24)}
    Get a list of all errors in the last 24hr

.EXAMPLE
    Get-LTErrors | Out-Gridview
    Open the log file in a sortable searchable window.

.NOTES
    Version:        1.3
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/18/2018
    Purpose/Change: Changed Erroraction from Stop to unspecified to allow caller to set the ErrorAction.

    Update Date: 1/26/2019
    Purpose/Change: Update for better international date parsing support. Function rename.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        $BasePath = $(Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand BasePath -EA 0)
        if (!$BasePath){$BasePath = "${env:windir}\LTSVC"}
    }#End Begin

    Process{
        if ($(Test-Path -Path "$BasePath\LTErrors.txt") -eq $False) {
            Write-Error "ERROR: Line $(LINENUM): Unable to find lelog."
            return
        }
        Try{
            $errors = Get-Content "$BasePath\LTErrors.txt"
            $errors = $errors -join ' ' -split '::: '
            foreach($Line in $Errors){
                $items = $Line -split "`t" -replace ' - ',''
                if ($items[1]){
                    $object = New-Object -TypeName PSObject
                    $object | Add-Member -MemberType NoteProperty -Name ServiceVersion -Value $items[0]
                    $object | Add-Member -MemberType NoteProperty -Name Timestamp -Value $(Try {[datetime]::Parse($items[1])} Catch {})
                    $object | Add-Member -MemberType NoteProperty -Name Message -Value $items[2]
                    Write-Output $object
                }
            }

        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error reading the log. $($Error[0])"
        }#End Catch
    }#End Process

    End{
        if ($?){
        }
        Else {$Error[0]}
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Get-LTErrors
Set-Alias -Name Get-LTError -Value Get-LTErrors

Function Reset-LTService{
<#
.SYNOPSIS
    This function will remove local settings on the agent.

.DESCRIPTION
    This function can remove some of the agents local settings.
    ID, MAC, LocationID
    The function will stop the services, make the change, then start the services.
    Resetting all of these will force the agent to check in as a new agent.
    If you have MAC filtering enabled it should check back in with the same ID.
    This function is useful for duplicate agents.

.PARAMETER ID
    This will reset the AgentID of the computer

.PARAMETER Location
    This will reset the LocationID of the computer

.PARAMETER MAC
    This will reset the MAC of the computer

.PARAMETER Force
    This will force operation on an agent detected as a probe.

.PARAMETER NoWait
    This will skip the ending health check for the reset process.
    The function will exit once the values specified have been reset.

.EXAMPLE
    Reset-LTService
    This resets the ID, MAC and LocationID on the agent.

.EXAMPLE
    Reset-LTService -ID
    This resets only the ID of the agent.

.NOTES
    Version:        1.4
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/12/2018
    Purpose/Change: Added detection of "Probe" enabled agent.
    Added support for -Force parameter to override probe detection. Added support for -WhatIf.
    Added support for -NoWait paramter to bypass agent health check.

    Update Date: 3/21/2018
    Purpose/Change: Removed ErrorAction Override

    Update Date: 8/5/2019
    Purpose/Change: Bugfixes for -Location parameter

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [switch]$ID,
        [switch]$Location,
        [switch]$MAC,
        [switch]$Force,
        [switch]$NoWait
    )

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

        $Reg = 'HKLM:\Software\LabTech\Service'
        If (!$PsBoundParameters.ContainsKey('ID') -and !$PsBoundParameters.ContainsKey('Location') -and !$PsBoundParameters.ContainsKey('MAC')){
            $ID=$True
            $Location=$True
            $MAC=$True
        }#End If

        $LTSI=Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
        If (($LTSI) -and ($LTSI|Select-Object -Expand Probe -EA 0) -eq '1') {
            If ($Force -eq $True) {
                Write-Output "Probe Agent Detected. Reset Forced."
            } Else {
                If ($WhatIfPreference -ne $True) {
                    Write-Error -Exception [System.OperationCanceledException]"ERROR: Line $(LINENUM): Probe Agent Detected. Reset Denied." -ErrorAction Stop
                } Else {
                    Write-Error -Exception [System.OperationCanceledException]"What If: Line $(LINENUM): Probe Agent Detected. Reset Denied." -ErrorAction Stop
                }#End If
            }#End If
        }#End If
        Write-Output "OLD ID: $($LTSI|Select-Object -Expand ID -EA 0) LocationID: $($LTSI|Select-Object -Expand LocationID -EA 0) MAC: $($LTSI|Select-Object -Expand MAC -EA 0)"
        $LTSI=$Null
    }#End Begin

    Process{
        If (!(Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
            If ($WhatIfPreference -ne $True) {
                Write-Error "ERROR: Line $(LINENUM): LabTech Services NOT Found $($Error[0])"
                return
            } Else {
                Write-Error "What If: Line $(LINENUM): Stopping: LabTech Services NOT Found"
                return
            }#End If
        }#End If

        Try{
            If ($ID -or $Location -or $MAC) {
                Stop-LTService
                If ($ID) {
                    Write-Output ".Removing ID"
                    Remove-ItemProperty -Name ID -Path $Reg -ErrorAction SilentlyContinue
                }#End If
                If ($Location) {
                    Write-Output ".Removing LocationID"
                    Remove-ItemProperty -Name LocationID -Path $Reg -ErrorAction SilentlyContinue
                }#End If
                If ($MAC) {
                    Write-Output ".Removing MAC"
                    Remove-ItemProperty -Name MAC -Path $Reg -ErrorAction SilentlyContinue
                }#End If
                Start-LTService
            }
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error during the reset process. $($Error[0])" -ErrorAction Stop
        }#End Catch
    }#End Process

    End{
        If ($?){
            If (-NOT $NoWait -and $PSCmdlet.ShouldProcess("LTService", "Discover new settings after Service Start")) {
                $timeout = New-Timespan -Minutes 1
                $sw = [diagnostics.stopwatch]::StartNew()
                $LTSI=Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
                Write-Host -NoNewline "Waiting for agent to register."
                While (!($LTSI|Select-Object -Expand ID -EA 0) -or !($LTSI|Select-Object -Expand LocationID -EA 0) -or !($LTSI|Select-Object -Expand MAC -EA 0) -and $($sw.elapsed) -lt $timeout){
                    Write-Host -NoNewline '.'
                    Start-Sleep 2
                    $LTSI=Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
                }#End While
                Write-Host ""
                $LTSI=Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
                Write-Output "NEW ID: $($LTSI|Select-Object -Expand ID -EA 0) LocationID: $($LTSI|Select-Object -Expand LocationID -EA 0) MAC: $($LTSI|Select-Object -Expand MAC -EA 0)"
            }#End If
        } Else {$Error[0]}
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Reset-LTService

Function Hide-LTAddRemove{
<#
.SYNOPSIS
    This function hides the LabTech install from the Add/Remove Programs list.

.DESCRIPTION
    This function will rename the DisplayName registry key to hide it from the Add/Remove Programs list.

.NOTES
    Version:        1.2
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/12/2018
    Purpose/Change: Support for ShouldProcess. Added Registry Paths to be checked.
    Modified hiding method to be compatible with standard software controls.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        $RegRoots = ('HKLM:\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
        'HKLM:\SOFTWARE\Classes\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC')
        $PublisherRegRoots = ('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}')
        $RegEntriesFound=0
        $RegEntriesChanged=0
    }#End Begin

    Process{

        Try{
            Foreach($RegRoot in $RegRoots){
                If (Test-Path $RegRoot){
                    If (Get-ItemProperty $RegRoot -Name HiddenProductName -ErrorAction SilentlyContinue) {
                        If (!(Get-ItemProperty $RegRoot -Name ProductName -ErrorAction SilentlyContinue)) {
                            Write-Verbose "LabTech found with HiddenProductName value."
                            Try{
                                Rename-ItemProperty $RegRoot -Name HiddenProductName -NewName ProductName
                            }#End Try
                            Catch{
                                Write-Error "ERROR: Line $(LINENUM): There was an error renaming the registry value. $($Error[0])" -ErrorAction Stop
                            }#End Catch
                        } Else {
                            Write-Verbose "LabTech found with unused HiddenProductName value."
                            Try{
                                Remove-ItemProperty $RegRoot -Name HiddenProductName -EA 0 -Confirm:$False -WhatIf:$False -Force
                            }#End Try
                            Catch{}#End Catch
                        }#End If
                    }#End If
                }#End If
            }#End Foreach

            Foreach($RegRoot in $PublisherRegRoots){
                If (Test-Path $RegRoot){
                    $RegKey=Get-Item $RegRoot -ErrorAction SilentlyContinue
                    If ($RegKey){
                        $RegEntriesFound++
                        If ($PSCmdlet.ShouldProcess("$($RegRoot)", "Set Registry Values to Hide $($RegKey.GetValue('DisplayName'))")){
                            $RegEntriesChanged++
                            @('SystemComponent') | ForEach-Object {
                                If (($RegKey.GetValue("$($_)")) -ne 1) {
                                    Write-Verbose "Setting $($RegRoot)\$($_)=1"
                                    Set-ItemProperty $RegRoot -Name "$($_)" -Value 1 -Type DWord -WhatIf:$False -Confirm:$False -Verbose:$False
                                }#End If
                            }#End ForEach-Object
                        }#End If
                    }#End If
                }#End If
            }#End Foreach
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error setting the registry values. $($Error[0])" -ErrorAction Stop
        }#End Catch

    }#End Process

    End{
        If ($WhatIfPreference -ne $True) {
            If ($?){
                If ($RegEntriesFound -gt 0 -and $RegEntriesChanged -eq $RegEntriesFound) {
                    Write-Output "LabTech is hidden from Add/Remove Programs."
                } Else {
                    Write-Warning "WARNING: Line $(LINENUM): LabTech may not be hidden from Add/Remove Programs."
                }#End If
            }#End If
            Else {$Error[0]}
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Hide-LTAddRemove

Function Show-LTAddRemove{
<#
.SYNOPSIS
    This function shows the LabTech install in the add/remove programs list.

.DESCRIPTION
    This function will rename the HiddenDisplayName registry key to show it in the add/remove programs list.
    If there is not HiddenDisplayName key the function will import a new entry.

.NOTES
    Version:        1.2
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/12/2018
    Purpose/Change: Support for ShouldProcess. Added Registry Paths to be checked.
    Modified hiding method to be compatible with standard software controls.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        $RegRoots = ('HKLM:\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
        'HKLM:\SOFTWARE\Classes\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC')
        $PublisherRegRoots = ('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}')
        $RegEntriesFound=0
        $RegEntriesChanged=0
    }#End Begin

    Process{

        Try{
            Foreach($RegRoot in $RegRoots){
                If (Test-Path $RegRoot){
                    If (Get-ItemProperty $RegRoot -Name HiddenProductName -ErrorAction SilentlyContinue) {
                        If (!(Get-ItemProperty $RegRoot -Name ProductName -ErrorAction SilentlyContinue)) {
                            Write-Verbose "LabTech found with HiddenProductName value."
                            Try{
                                Rename-ItemProperty $RegRoot -Name HiddenProductName -NewName ProductName
                            }#End Try
                            Catch{
                                Write-Error "ERROR: Line $(LINENUM): There was an error renaming the registry value. $($Error[0])" -ErrorAction Stop
                            }#End Catch
                        } Else {
                            Write-Verbose "LabTech found with unused HiddenProductName value."
                            Try{
                                Remove-ItemProperty $RegRoot -Name HiddenProductName -EA 0 -Confirm:$False -WhatIf:$False -Force
                            }#End Try
                            Catch{}#End Catch
                        }#End If
                    }#End If
                }#End If
            }#End Foreach

            Foreach($RegRoot in $PublisherRegRoots){
                If (Test-Path $RegRoot){
                    $RegKey=Get-Item $RegRoot -ErrorAction SilentlyContinue
                    If ($RegKey){
                        $RegEntriesFound++
                        If ($PSCmdlet.ShouldProcess("$($RegRoot)", "Set Registry Values to Show $($RegKey.GetValue('DisplayName'))")){
                            $RegEntriesChanged++
                            @('SystemComponent') | ForEach-Object {
                                If (($RegKey.GetValue("$($_)")) -eq 1) {
                                    Write-Verbose "Setting $($RegRoot)\$($_)=0"
                                    Set-ItemProperty $RegRoot -Name "$($_)" -Value 0 -Type DWord -WhatIf:$False -Confirm:$False -Verbose:$False
                                }#End If
                            }#End ForEach-Object
                        }#End If
                    }#End If
                }#End If
            }#End Foreach
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error setting the registry values. $($Error[0])" -ErrorAction Stop
        }#End Catch

    }#End Process

    End{
        If ($WhatIfPreference -ne $True) {
            If ($?){
                If ($RegEntriesFound -gt 0 -and $RegEntriesChanged -eq $RegEntriesFound) {
                    Write-Output "LabTech is visible from Add/Remove Programs."
                } Else {
                    Write-Warning "WARNING: Line $(LINENUM): LabTech may not be visible from Add/Remove Programs."
                }#End If
            }#End If
            Else {$Error[0]}
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Show-LTAddRemove

Function Test-LTPorts{
<#
.SYNOPSIS
    This function will attempt to connect to all required TCP ports.

.DESCRIPTION
    The function will confirm the LTTray port is available locally.
    It will then test required TCP ports to the Server.

.PARAMETER Server
    This is the URL to your LabTech server.
    Example: https://lt.domain.com
    If no server is provided the function will use Get-LTServiceInfo to
    get the server address. If it is unable to find LT currently installed
    it will try calling Get-LTServiceInfoBackup.

.PARAMETER TrayPort
    This is the port LTSvc.exe listens on for communication with LTTray.
    It will be checked to verify it is available. If not provided the
    default port will be used (42000).

.PARAMETER Quiet
    This will return a boolean for connectivity status to the Server

.NOTES
    Version:        1.6
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date:    5/11/2017
    Purpose/Change: Quiet feature

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 6/10/2017
    Purpose/Change: Updates for pipeline input, support for multiple servers

    Update Date: 8/24/2017
    Purpose/Change: Update to use Clear-Variable.

    Update Date: 8/29/2017
    Purpose/Change: Added Server Address Format Check

    Update Date: 2/13/2018
    Purpose/Change: Added -TrayPort parameter.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipelineByPropertyName = $true, ValueFromPipeline=$True)]
        [string[]]$Server,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [int]$TrayPort,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]$Quiet
    )

    Begin{
        Function Private:TestPort{
        Param(
            [parameter(Position=0)]
            [string]
            $ComputerName,

            [parameter(Mandatory=$False)]
            [System.Net.IPAddress]
            $IPAddress,

            [parameter(Mandatory=$True , Position=1)]
            [int]
            $Port
            )

        $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) {$IPAddress} Else {$ComputerName};
        If ([string]::IsNullOrEmpty($RemoteServer)) {Write-Error "ERROR: Line $(LINENUM): No ComputerName or IPAddress was provided to test."; return}

        $test = New-Object System.Net.Sockets.TcpClient;
        Try
        {
            Write-Output "Connecting to $($RemoteServer):$Port (TCP)..";
            $test.Connect($RemoteServer, $Port);
            Write-Output "Connection successful";
        }
        Catch
        {
            Write-Output "ERROR: Connection failed";
            $Global:PortTestError = 1
        }
        Finally
        {
            $test.Close();
        }

        }#End Function TestPort

        Clear-Variable CleanSvr,svr,proc,processes,port,netstat,line -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

    }#End Begin

    Process{
        If (-not ($Server) -and (-not ($TrayPort) -or -not ($Quiet))){
            Write-Verbose 'No Server Input - Checking for names.'
            $Server = Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand 'Server' -EA 0
            If (-not ($Server)){
                Write-Verbose 'No Server found in installed Service Info. Checking for Service Backup.'
                $Server = Get-LTServiceInfoBackup -EA 0 -Verbose:$False|Select-Object -Expand 'Server' -EA 0
            }#End If
        }#End If

        If (-not ($Quiet) -or (($TrayPort) -ge 1 -and ($TrayPort) -le 65530)){
            If (-not ($TrayPort) -or -not (($TrayPort) -ge 1 -and ($TrayPort) -le 65530)){
                #Learn LTTrayPort if available.
                $TrayPort = (Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand TrayPort -EA 0)
            }
            If (-not ($TrayPort) -or $TrayPort -notmatch '^\d+$') {$TrayPort=42000}

            [array]$processes = @()
            #Get all processes that are using LTTrayPort (Default 42000)
            Try {$netstat=& "${env:windir}\system32\netstat.exe" -a -o -n | Select-String -Pattern " .*[0-9\.]+:$($TrayPort).*[0-9\.]+:[0-9]+ .*?([0-9]+)" -EA 0}
            Catch {Write-Output "Error calling netstat.exe."; $netstat=$null}
            Foreach ($line In $netstat){
                $processes += ($line -split ' {4,}')[-1]
            }
            $processes = $processes | Where-Object {$_ -gt 0 -and $_ -match '^\d+$'}| Sort-Object | Get-Unique
            If (($processes)) {
                If (-not ($Quiet)){
                    Foreach ($proc In $processes) {
                        If ((Get-Process -ID $proc -EA 0|Select-Object -Expand ProcessName -EA 0) -eq 'LTSvc') {
                            Write-Output "TrayPort Port $TrayPort is being used by LTSvc."
                        } Else {
                            Write-Output "Error: TrayPort Port $TrayPort is being used by $(Get-Process -ID $proc|Select-Object -Expand ProcessName -EA 0)."
                        }#End If
                    }#End Foreach
                } Else {return $False}#End If
            } ElseIf (($Quiet) -eq $True){
                return $True
            } Else {
                Write-Output "TrayPort Port $TrayPort is available."
            }#End If
        }#End If

        foreach ($svr in $Server) {
            if ($Quiet){
                Test-Connection $Svr -Quiet
                return
            }

            If ($Svr -match '^(https?://)?(([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}|[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*)$') {
                Try{
                    $CleanSvr = ($Svr -replace 'https?://',''|ForEach-Object {$_.Trim()})
                    Write-Output "Testing connectivity to required TCP ports:"
                    TestPort -ComputerName $CleanSvr -Port 70
                    TestPort -ComputerName $CleanSvr -Port 80
                    TestPort -ComputerName $CleanSvr -Port 443
                    TestPort -ComputerName mediator.labtechsoftware.com -Port 8002

                }#End Try

                Catch{
                    Write-Error "ERROR: Line $(LINENUM): There was an error testing the ports. $($Error[0])" -ErrorAction Stop
                }#End Catch
            } Else {
                Write-Warning "WARNING: Line $(LINENUM): Server address $($Svr) is not a valid address or is not formatted correctly. Example: https://lt.domain.com"
            }#End If
        }#End Foreach
    }#End Process

    End{
        If ($?){
            if (-not ($Quiet)){
                Write-Output "Test-LTPorts Finished"
            }
        }
        Else{$Error[0]}
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Test-LTPorts

Function Get-LTLogging{
<#
.SYNOPSIS
    This function will return the logging level of the LabTech service.

.NOTES
    Version:        1.1
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/18/2018
    Purpose/Change: Changed Erroraction from Stop to unspecified to allow caller to set the ErrorAction.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param ()

    Begin{
        Write-Verbose "Checking for registry keys."
    }#End Begin

    Process{
        Try{
            $Value = (Get-LTServiceSettings|Select-Object -Expand Debuging -EA 0)
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was a problem reading the registry key. $($Error[0])"
            return
        }#End Catch
    }#End Process

    End{
        if ($?){
            if ($value -eq 1){
                Write-Output "Current logging level: Normal"
            }
            elseif ($value -eq 1000){
                Write-Output "Current logging level: Verbose"
            }
            else{
                Write-Error "ERROR: Line $(LINENUM): Unknown Logging level $($value)"
            }
        }
    }#End End
}#End Function Get-LTLogging

Function Set-LTLogging{
<#
.SYNOPSIS
        This function will set the logging level of the LabTech service.

.NOTES
    Version:        1.1
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

.LINK
    http://labtechconsulting.com
#>
    Param (
        [switch]$Normal,
        [switch]$Verbose
    )

    Begin{
    if ($Normal -ne $true -and $Verbose -ne $true ){
        Write-Error "ERROR: Line $(LINENUM): Please provide a logging level. -Normal or -Verbose" -ErrorAction Stop
    }
    }#End Begin

    Process{
    Try{
        Stop-LTService
        if ($Normal){
            Set-ItemProperty HKLM:\SOFTWARE\LabTech\Service\Settings -Name 'Debuging' -Value 1
        }
        if ($Verbose){
            Set-ItemProperty HKLM:\SOFTWARE\LabTech\Service\Settings -Name 'Debuging' -Value 1000
        }
        Start-LTService
    }#End Try

    Catch{
      Write-Error "ERROR: Line $(LINENUM): There was a problem writing the registry key. $($Error[0])" -ErrorAction Stop
    }#End Catch
    }#End Process

    End{
    if ($?){
        Get-LTLogging
    }
    }#End End
}#End Function Set-LTLogging

Function Get-LTProbeErrors{
<#
.SYNOPSIS
    This will pull the %ltsvcdir%\LTProbeErrors.txt file into an object.

.EXAMPLE
    Get-LTProbeErrors | where {(Get-date $_.Time) -gt (get-date).AddHours(-24)}
    Get a list of all errors in the last 24hr

.EXAMPLE
    Get-LTProbeErrors | Out-Gridview
    Open the log file in a sortable searchable window.

.NOTES
    Version:        1.3
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/18/2018
    Purpose/Change: Changed Erroraction from Stop to unspecified to allow caller to set the ErrorAction.

    Update Date: 1/26/2019
    Purpose/Change: Update for better international date parsing support

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param()

    Begin{
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        $BasePath = $(Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand BasePath -EA 0)
        if (!($BasePath)){$BasePath = "${env:windir}\LTSVC"}
    }#End Begin

    Process{
        if ($(Test-Path -Path "$BasePath\LTProbeErrors.txt") -eq $False) {
            Write-Error "ERROR: Line $(LINENUM): Unable to find log."
            return
        }
        $errors = Get-Content "$BasePath\LTProbeErrors.txt"
        $errors = $errors -join ' ' -split '::: '
        Try {
            Foreach($Line in $Errors){
                $items = $Line -split "`t" -replace ' - ',''
                $object = New-Object -TypeName PSObject
                $object | Add-Member -MemberType NoteProperty -Name ServiceVersion -Value $items[0]
                $object | Add-Member -MemberType NoteProperty -Name Timestamp -Value $(Try {[datetime]::Parse($items[1])} Catch {})
                $object | Add-Member -MemberType NoteProperty -Name Message -Value $items[2]
                Write-Output $object
            }#End Foreach
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error reading the log. $($Error[0])"
        }#End Catch
    }

    End{
        if ($?){
        }
        Else {$Error[0]}
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function Get-LTProbeErrors

Function New-LTServiceBackup{
<#
.SYNOPSIS
    This function will backup all the reg keys to 'HKLM\SOFTWARE\LabTechBackup'
    This will also backup those files to "$((Get-LTServiceInfo).BasePath)Backup"

.NOTES
    Version:        1.4
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  5/11/2017
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 6/7/2017
    Purpose/Change: Updated error handling.

    Update Date: 8/24/2017
    Purpose/Change: Update to use Clear-Variable.

    Update Date: 3/21/2017
    Purpose/Change: Added additional Debug Output

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param ()

    Begin{
        Clear-Variable LTPath,BackupPath,Keys,Path,Result,Reg,RegPath -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

        $LTPath = "$(Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False|Select-Object -Expand BasePath -EA 0)"
        if (-not ($LTPath)) {
            Write-Error "ERROR: Line $(LINENUM): Unable to find LTSvc folder path." -ErrorAction Stop
        }
        $BackupPath = "$($LTPath)Backup"
        $Keys = "HKLM\SOFTWARE\LabTech"
        $RegPath = "$BackupPath\LTBackup.reg"

        Write-Verbose "Checking for registry keys."
        if ((Test-Path ($Keys -replace '^(H[^\\]*)','$1:')) -eq $False){
            Write-Error "ERROR: Line $(LINENUM): Unable to find registry information on LTSvc. Make sure the agent is installed." -ErrorAction Stop
        }
        if ($(Test-Path -Path $LTPath -PathType Container) -eq $False) {
            Write-Error "ERROR: Line $(LINENUM): Unable to find LTSvc folder path $LTPath" -ErrorAction Stop
        }
        New-Item $BackupPath -type directory -ErrorAction SilentlyContinue | Out-Null
        if ($(Test-Path -Path $BackupPath -PathType Container) -eq $False) {
            Write-Error "ERROR: Line $(LINENUM): Unable to create backup folder path $BackupPath" -ErrorAction Stop
        }
    }#End Begin

    Process{
        Try{
            Copy-Item $LTPath $BackupPath -Recurse -Force
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was a problem backing up the LTSvc Folder. $($Error[0])"
        }#End Catch

        Try{
            Write-Debug "Line $(LINENUM): Exporting Registry Data"
            $Null = & "${env:windir}\system32\reg.exe" export "$Keys" "$RegPath" /y 2>''
            Write-Debug "Line $(LINENUM): Loading and modifying registry key name"
            $Reg = Get-Content $RegPath
            $Reg = $Reg -replace [Regex]::Escape('[HKEY_LOCAL_MACHINE\SOFTWARE\LabTech'),'[HKEY_LOCAL_MACHINE\SOFTWARE\LabTechBackup'
            Write-Debug "Line $(LINENUM): Writing output information"
            $Reg | Out-File $RegPath
            Write-Debug "Line $(LINENUM): Importing Registry data to Backup Path"
            $Null = & "${env:windir}\system32\reg.exe" import "$RegPath" 2>''
            $True | Out-Null #Protection to prevent exit status error
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was a problem backing up the LTSvc Registry keys. $($Error[0])"
        }#End Catch
    }#End Process

    End{
        If ($?){
            Write-Output "The LabTech Backup has been created."
        } Else {
            Write-Error "ERROR: Line $(LINENUM): There was a problem completing the LTSvc Backup. $($Error[0])"
        }#End If
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End
}#End Function New-LTServiceBackup

Function Get-LTServiceInfoBackup{
<#
.SYNOPSIS
    This function will pull all of the backed up registry data into an object.

.NOTES
    Version:        1.1
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  5/11/2017
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/18/2018
    Purpose/Change: Changed Erroraction from Stop to unspecified to allow caller to set the ErrorAction.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param ()

    Begin{
        Write-Verbose "Checking for registry keys."
        $exclude = "PSParentPath","PSChildName","PSDrive","PSProvider","PSPath"
    }#End Begin

    Process{
        If ((Test-Path 'HKLM:\SOFTWARE\LabTechBackup\Service') -eq $False){
            Write-Error "ERROR: Line $(LINENUM): Unable to find backup information on LTSvc. Use New-LTServiceBackup to create a settings backup."
            return
        }
        Try{
            $key = Get-ItemProperty HKLM:\SOFTWARE\LabTechBackup\Service -ErrorAction Stop | Select-Object * -exclude $exclude
            If ($Null -ne $key -and ($key|Get-Member|Where-Object {$_.Name -match 'BasePath'})) {
                $key.BasePath = [System.Environment]::ExpandEnvironmentVariables($key.BasePath) -replace '\\\\','\'
            }
            If ($Null -ne $key -and ($key|Get-Member|Where-Object {$_.Name -match 'Server Address'})) {
                $Servers = ($Key|Select-Object -Expand 'Server Address' -EA 0).Split('|')|ForEach-Object {$_.Trim()}
                Add-Member -InputObject $key -MemberType NoteProperty -Name 'Server' -Value $Servers -Force
            }
        }#End Try
        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was a problem reading the backup registry keys. $($Error[0])"
            return
        }#End Catch
    }#End Process

    End{
        If ($?){
            return $key
        }
    }#End End
}#End Function Get-LTServiceInfoBackup

Function Rename-LTAddRemove{
<#
.SYNOPSIS
    This function renames the LabTech install as shown in the Add/Remove Programs list.

.DESCRIPTION
    This function will change the value of the DisplayName registry key to effect Add/Remove Programs list.

.PARAMETER Name
    This is the Name for the LabTech Agent as displayed in the list of installed software.

.PARAMETER PublisherName
    This is the Name for the Publisher of the LabTech Agent as displayed in the list of installed software.

.NOTES
    Version:        1.2
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  5/14/2017
    Purpose/Change: Initial script development

    Update Date: 6/1/2017
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/12/2018
    Purpose/Change: Support for ShouldProcess to enable -Confirm and -WhatIf.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(Mandatory=$True)]
        $Name,

        [Parameter(Mandatory=$False)]
        [AllowNull()]
        [string]$PublisherName
    )

    Begin{
        $RegRoots = ('HKLM:\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
        'HKLM:\SOFTWARE\Classes\Installer\Products\D1003A85576B76D45A1AF09A0FC87FAC')
        $PublisherRegRoots = ('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}')
        $RegNameFound=0;
        $RegPublisherFound=0;
    }#End Begin

    Process{
        Try{
            foreach($RegRoot in $RegRoots){
                if (Get-ItemProperty $RegRoot -Name ProductName -ErrorAction SilentlyContinue){
                    If ($PSCmdlet.ShouldProcess("$($RegRoot)\ProductName=$($Name)", "Set Registry Value")) {
                        Write-Verbose "Setting $($RegRoot)\ProductName=$($Name)"
                        Set-ItemProperty $RegRoot -Name ProductName -Value $Name -Confirm:$False
                        $RegNameFound++
                    }#End If
                } ElseIf (Get-ItemProperty $RegRoot -Name HiddenProductName -ErrorAction SilentlyContinue){
                    If ($PSCmdlet.ShouldProcess("$($RegRoot)\HiddenProductName=$($Name)", "Set Registry Value")) {
                        Write-Verbose "Setting $($RegRoot)\HiddenProductName=$($Name)"
                        Set-ItemProperty $RegRoot -Name HiddenProductName -Value $Name -Confirm:$False
                        $RegNameFound++
                    }#End If
                }
            }#End Foreach
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error setting the registry key value. $($Error[0])" -ErrorAction Stop
        }#End Catch

        If (($PublisherName)){
            Try{
                Foreach($RegRoot in $PublisherRegRoots){
                    If (Get-ItemProperty $RegRoot -Name Publisher -ErrorAction SilentlyContinue){
                        If ($PSCmdlet.ShouldProcess("$($RegRoot)\Publisher=$($PublisherName)", "Set Registry Value")) {
                            Write-Verbose "Setting $($RegRoot)\Publisher=$($PublisherName)"
                            Set-ItemProperty $RegRoot -Name Publisher -Value $PublisherName -Confirm:$False
                            $RegPublisherFound++
                        }#End If
                    }#End If
                }#End Foreach
            }#End Try

            Catch{
                Write-Error "ERROR: Line $(LINENUM): There was an error setting the registry key value. $($Error[0])" -ErrorAction Stop
            }#End Catch
        }#End If
    }#End Process

    End{
        If ($WhatIfPreference -ne $True) {
            If ($?){
                If ($RegNameFound -gt 0) {
                    Write-Output "LabTech is now listed as $($Name) in Add/Remove Programs."
                } Else {
                    Write-Warning "WARNING: Line $(LINENUM): LabTech was not found in installed software and the Name was not changed."
                }#End If
                If (($PublisherName)){
                    If ($RegPublisherFound -gt 0) {
                        Write-Output "The Publisher is now listed as $($PublisherName)."
                    } Else {
                        Write-Warning "WARNING: Line $(LINENUM): LabTech was not found in installed software and the Publisher was not changed."
                    }
                }#End If
            } Else {$Error[0]}
        }#End If
    }#End End
}#End Function Rename-LTAddRemove

Function Invoke-LTServiceCommand {
<#
.SYNOPSIS
    This function tells the agent to execute the desired command.

.DESCRIPTION
    This function will allow you to execute all known commands against an agent.

.NOTES
    Version:        1.2
    Author:         Chris Taylor
    Website:        labtechconsulting.com
    Creation Date:  2/2/2018
    Purpose/Change: Initial script development
    Thanks:         Gavin Stone, for finding the command list

    Update Date: 2/8/2018
    Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2

    Update Date: 3/21/2018
    Purpose/Change: Removed ErrorAction Override

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$True)]
        [ValidateSet("Update Schedule",
                     "Send Inventory",
                     "Send Drives",
                     "Send Processes",
                     "Send Spyware List",
                     "Send Apps",
                     "Send Events",
                     "Send Printers",
                     "Send Status",
                     "Send Screen",
                     "Send Services",
                     "Analyze Network",
                     "Write Last Contact Date",
                     "Kill VNC",
                     "Kill Trays",
                     "Send Patch Reboot",
                     "Run App Care Update",
                     "Start App Care Daytime Patching")][string[]]$Command
    )

    Begin {
        $Service = Get-Service 'LTService'
    }

    Process {
        If (-not ($Service)) {Write-Warning "WARNING: Line $(LINENUM): Service 'LTService' was not found. Cannot send service command"; return}
        If ($Service.Status -ne 'Running') {Write-Warning "WARNING: Line $(LINENUM): Service 'LTService' is not running. Cannot send service command"; return}
        Foreach ($Cmd in $Command) {
            $CommandID=$Null
            Try{
                switch($Cmd){
                    'Update Schedule' {$CommandID = 128}
                    'Send Inventory' {$CommandID = 129}
                    'Send Drives' {$CommandID = 130}
                    'Send Processes' {$CommandID = 131}
                    'Send Spyware List'{$CommandID = 132}
                    'Send Apps' {$CommandID = 133}
                    'Send Events' {$CommandID = 134}
                    'Send Printers' {$CommandID = 135}
                    'Send Status' {$CommandID = 136}
                    'Send Screen' {$CommandID = 137}
                    'Send Services' {$CommandID = 138}
                    'Analyze Network' {$CommandID = 139}
                    'Write Last Contact Date' {$CommandID = 140}
                    'Kill VNC' {$CommandID = 141}
                    'Kill Trays' {$CommandID = 142}
                    'Send Patch Reboot' {$CommandID = 143}
                    'Run App Care Update' {$CommandID = 144}
                    'Start App Care Daytime Patching' {$CommandID = 145}
                    default {"Invalid entry"}
                }
                If ($PSCmdlet.ShouldProcess("LTService", "Send Service Command '$($Cmd)' ($($CommandID))")) {
                    If ($Null -ne $CommandID) {
                        Write-Debug "Line $(LINENUM): Sending service command '$($Cmd)' ($($CommandID)) to 'LTService'"
                        Try {
                            $Null=& "${env:windir}\system32\sc.exe" control LTService $($CommandID) 2>''
                            Write-Output "Sent Command '$($Cmd)' to 'LTService'"
                        }
                        Catch {
                            Write-Output "Error calling sc.exe. Failed to send command."
                        }
                    }#End If
                }#End If
            } # End Try

            Catch{
                Write-Warning ("WARNING: Line $(LINENUM)",$_.Exception)
            } # End Catch
        } # End Foreach
    } # End Process

    End{}

} # End Function Invoke-LTServiceCommand

Function Initialize-LTServiceKeys{
<#
.SYNOPSIS
    This function initializes internal variables needed by other functions

.DESCRIPTION
    This function will set variables for the Agent and Server passwords needed
    for encoding and decoding steps. Nothing is returned.

.NOTES
    Version:        1.1
    Author:         Darren White
    Creation Date:  1/25/2018
    Purpose/Change: Initial function development

    Update Date: 3/18/2018
    Purpose/Change: Rename to Initialize-LTServiceKeys from Get-LTServiceKeys

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param(
    )

    Process {
        $LTSI=Get-LTServiceInfo -EA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
        If (($LTSI) -and ($LTSI|Get-Member|Where-Object {$_.Name -eq 'ServerPassword'})) {
            Write-Debug "Line $(LINENUM): Decoding Server Password."
            $Script:LTServiceKeys.ServerPasswordString=$(ConvertFrom-LTSecurity -InputString "$($LTSI.ServerPassword)")
            If ($Null -ne $LTSI -and ($LTSI|Get-Member|Where-Object {$_.Name -eq 'Password'})) {
                Write-Debug "Line $(LINENUM): Decoding Agent Password."
                $Script:LTServiceKeys.PasswordString=$(ConvertFrom-LTSecurity -InputString "$($LTSI.Password)" -Key "$($Script:LTServiceKeys.ServerPasswordString)")
            } Else {
                $Script:LTServiceKeys.PasswordString=''
            }
        } Else {
            $Script:LTServiceKeys.ServerPasswordString=''
            $Script:LTServiceKeys.PasswordString=''
        }
    }#End Process

    End {
    }#End End
}#End Function Initialize-LTServiceKeys

Function ConvertFrom-LTSecurity{
<#
.SYNOPSIS
    This function decodes an encoded Base64 value

.DESCRIPTION
    This function decodes the provided string using the specified or default key.

.PARAMETER InputString
    This is the string to be decoded.

.PARAMETER Key
    This is the key used for decoding. If not provided, default values will be tried.

.PARAMETER Force
    This forces the function to try alternate key values if decoding fails using provided key.

.NOTES
    Version:        1.2
    Author:         Darren White
    Creation Date:  1/25/2018
    Purpose/Change: Initial function development

    Update Date: 6/25/2020
    Purpose/Change: Improved pipeline and parameter handling

.LINK
    http://labtechconsulting.com
#>
[CmdletBinding(SupportsShouldProcess=$True)]
Param(
    [parameter(Mandatory = $true, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Position = 1)]
    [string[]]$InputString,

    [parameter(Mandatory = $false, ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $True)]
    [AllowNull()]
    [AllowEmptyString()]
    [AllowEmptyCollection()]
    $Key = $Null,

    [parameter(Mandatory = $false, ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
    [switch]$Force=$True
)

    Begin {
        $DefaultKey='Thank you for using LabTech.'
        $_initializationVector = [byte[]](240, 3, 45, 29, 0, 76, 173, 59)
        $NoKeyPassed=$False
        $DecodedString=$Null
        $DecodeString=$Null
    }#End Begin

    Process {
        If ($Null -eq $Key) {
            $NoKeyPassed=$True
            $Key=$DefaultKey
        }
        foreach ($testInput in $InputString) {
            $DecodeString=$Null
            foreach ($testKey in $Key) {
                If ($Null -eq $DecodeString) {
                    If ($Null -eq $testKey) {
                        $NoKeyPassed=$True
                        $testKey=$DefaultKey
                    }#End If
                    Write-Debug "Line $(LINENUM): Attempting Decode for '$($testInput)' with Key '$($testKey)'"
                    Try {
                        $numarray=[System.Convert]::FromBase64String($testInput)
                        $ddd = new-object System.Security.Cryptography.TripleDESCryptoServiceProvider
                        $ddd.key=(new-Object Security.Cryptography.MD5CryptoServiceProvider).ComputeHash([Text.Encoding]::UTF8.GetBytes($testKey))
                        $ddd.IV=$_initializationVector
                        $dd=$ddd.CreateDecryptor()
                        $DecodeString=[System.Text.Encoding]::UTF8.GetString($dd.TransformFinalBlock($numarray,0,($numarray.Length)))
                        $DecodedString+=@($DecodeString)
                    } Catch {
                    }#End Catch

                    Finally {
                        if ((Get-Variable -Name dd -Scope 0 -EA 0)) {try {$dd.Dispose()} catch {$dd.Clear()}}
                        if ((Get-Variable -Name ddd -Scope 0 -EA 0)) {try {$ddd.Dispose()} catch {$ddd.Clear()}}
                    }#End Finally
                } Else {
                }#End If
            }#End foreach
            If ($Null -eq $DecodeString) {
                If ($Force) {
                    If (($NoKeyPassed)) {
                        $DecodeString=ConvertFrom-LTSecurity -InputString "$($testInput)" -Key '' -Force:$False
                        If (-not ($Null -eq $DecodeString)) {
                            $DecodedString+=@($DecodeString)
                        }
                    } Else {
                        $DecodeString=ConvertFrom-LTSecurity -InputString "$($testInput)"
                        if (-not ($Null -eq $DecodeString)) {
                            $DecodedString+=@($DecodeString)
                        }
                    }#End If
                } Else {
                }#End If
            }#End If
        }#End foreach
    }#End Process

    End {
        If ($Null -eq $DecodedString) {
            Write-Debug "Line $(LINENUM): Failed to Decode string: '$($InputString)'"
            return $Null
        } else {
            return $DecodedString
        }#End If
    }#End End

}#End Function ConvertFrom-LTSecurity

Function ConvertTo-LTSecurity{
<#
.SYNOPSIS
    This function encodes a value compatible with LT operations.

.DESCRIPTION
    This function encodes the provided string using the specified or default key.

.PARAMETER InputString
    This is the string to be encoded.

.PARAMETER Key
    This is the key used for encoding. If not provided, a default value will be used.

.NOTES
    Version:        1.2
    Author:         Darren White
    Creation Date:  1/25/2018
    Purpose/Change: Initial function development

    Update Date: 6/23/2020
    Purpose/Change: Improved pipeline and parameter handling

.LINK
    http://labtechconsulting.com
#>
[CmdletBinding(SupportsShouldProcess=$True)]
Param(
    [parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 1)]
    [AllowNull()]
    [AllowEmptyString()]
    [AllowEmptyCollection()]
    [string[]]$InputString,
    [parameter(Mandatory = $false, ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [AllowNull()]
    [AllowEmptyString()]
    [AllowEmptyCollection()]
    $Key = $Null
)

    Begin {
        $_initializationVector = [byte[]](240, 3, 45, 29, 0, 76, 173, 59)
        $DefaultKey='Thank you for using LabTech.'
        $str=@()
    }#End Begin

    Process {
        foreach ($testInput in $InputString) {
            If ($Null -eq $Key) {
                $Key=$DefaultKey
            }#End If

            try {
                $numarray=[System.Text.Encoding]::UTF8.GetBytes($testInput)
            } catch {
                try { $numarray=[System.Text.Encoding]::ASCII.GetBytes($testInput) } catch {}
            }
            Write-Debug "Line $(LINENUM): Attempting Encode for '$($testInput)' with Key '$($Key)'"
            try {
                $ddd = new-object System.Security.Cryptography.TripleDESCryptoServiceProvider
                $ddd.key=(new-Object Security.Cryptography.MD5CryptoServiceProvider).ComputeHash([Text.Encoding]::UTF8.GetBytes($Key))
                $ddd.IV=$_initializationVector
                $dd=$ddd.CreateEncryptor()
                $str+=[System.Convert]::ToBase64String($dd.TransformFinalBlock($numarray,0,($numarray.Length)))
            }
            catch {
                Write-Debug "Line $(LINENUM): Failed to Encode string: '$($InputString)'"
                $str+=''
            }
            Finally
            {
                if ($dd) {try {$dd.Dispose()} catch {$dd.Clear()}}
                if ($ddd) {try {$ddd.Dispose()} catch {$ddd.Clear()}}
            }
        }#End ForEach
    }#End Process

    End {
        return $str
    }#End End
}#End Function ConvertTo-LTSecurity

Function Set-LTProxy{
<#
.SYNOPSIS
    This function configures module functions to use the specified proxy
    configuration for all operations as long as the module remains loaded.

.DESCRIPTION
    This function will set or clear Proxy settings needed for function and
    agent operations. If an agent is already installed, this function will
    set the ProxyUsername, ProxyPassword, and ProxyServerURL values for the
    Agent.
    NOTE: Agent Services will be restarted for changes (if found) to be applied.

.PARAMETER ProxyServerURL
    This is the URL and Port to assign as the ProxyServerURL for Module
    operations during this session and for the Installed Agent (if present).
    Example: Set-LTProxy -ProxyServerURL 'proxyhostname.fqdn.com'
    Example: Set-LTProxy -ProxyServerURL 'proxyhostname.fqdn.com:8080'
    This parameter may be used with the additional following parameters:
    ProxyUsername, ProxyPassword, EncodedProxyUsername, EncodedProxyPassword

.PARAMETER ProxyUsername
    This is the plain text Username for Proxy operations.
    Example: Set-LTProxy -ProxyServerURL 'proxyhostname.fqdn.com:8080' -ProxyUsername 'Test-User' -ProxyPassword 'SomeFancyPassword'

.PARAMETER ProxyPassword
    This is the plain text Password for Proxy operations.

.PARAMETER EncodedProxyUsername
    This is the encoded Username for Proxy operations. The parameter must be
    encoded with the Agent Password. This Parameter will be decoded using the
    Agent Password, and the decoded string will be configured.
    NOTE: Reinstallation of the Agent will generate a new agent password.
    Example: Set-LTProxy -ProxyServerURL 'proxyhostname.fqdn.com:8080' -EncodedProxyUsername '1GzhlerwMy0ElG9XNgiIkg==' -EncodedProxyPassword 'Duft4r7fekTp5YnQL9F0V9TbP7sKzm0n'

.PARAMETER EncodedProxyPassword
    This is the encoded Password for Proxy operations. The parameter must be
    encoded with the Agent Password. This Parameter will be decoded using the
    Agent Password, and the decoded string will be configured.
    NOTE: Reinstallation of the Agent will generate a new password.

.PARAMETER DetectProxy
    This parameter attempts to automatically detect the system Proxy settings
    for Module operations during this session. Discovered settings will be
    assigned to the Installed Agent (if present).
    Example: Set-LTProxy -DetectProxy
    This parameter may not be used with other parameters.

.PARAMETER ResetProxy
    This parameter clears any currently defined Proxy Settings for Module
    operations during this session. Discovered settings will be assigned
    to the Installed Agent (if present).
    Example: Set-LTProxy -ResetProxy
    This parameter may not be used with other parameters.

.NOTES
    Version:        1.1
    Author:         Darren White
    Creation Date:  1/24/2018
    Purpose/Change: Initial function development

.LINK
    http://labtechconsulting.com
#>

    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [parameter(Mandatory = $False, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Position = 0)]
        [string]$ProxyServerURL,

        [parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $True, Position = 1)]
        [string]$ProxyUsername,

        [parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $True, Position = 2)]
        [string]$ProxyPassword,

        [parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $True)]
        [string]$EncodedProxyUsername,

        [parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $True)]
        [string]$EncodedProxyPassword,

        [parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $True)]
        [alias('Detect')]
        [alias('AutoDetect')]
        [switch]$DetectProxy,

        [parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $True)]
        [alias('Clear')]
        [alias('Reset')]
        [alias('ClearProxy')]
        [switch]$ResetProxy
    )

    Begin {
        Clear-Variable LTServiceSettingsChanged,LTSS,LTServiceRestartNeeded,proxyURL,proxyUser,proxyPass,passwd,Svr -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"

        try {
            $LTSS=Get-LTServiceSettings -EA 0 -Verbose:$False -WA 0 -Debug:$False
        } catch {}

    }#End Begin

    Process{

        If (
(($ResetProxy -eq $True) -and (($DetectProxy -eq $True) -or ($ProxyServerURL) -or ($ProxyUsername) -or ($ProxyPassword) -or ($EncodedProxyUsername) -or ($EncodedProxyPassword))) -or
(($DetectProxy -eq $True) -and (($ResetProxy -eq $True) -or ($ProxyServerURL) -or ($ProxyUsername) -or ($ProxyPassword) -or ($EncodedProxyUsername) -or ($EncodedProxyPassword))) -or
((($ProxyServerURL) -or ($ProxyUsername) -or ($ProxyPassword) -or ($EncodedProxyUsername) -or ($EncodedProxyPassword)) -and (($ResetProxy -eq $True) -or ($DetectProxy -eq $True))) -or
((($ProxyUsername) -or ($ProxyPassword)) -and (-not ($ProxyServerURL) -or ($EncodedProxyUsername) -or ($EncodedProxyPassword) -or ($ResetProxy -eq $True) -or ($DetectProxy -eq $True))) -or
((($EncodedProxyUsername) -or ($EncodedProxyPassword)) -and (-not ($ProxyServerURL) -or ($ProxyUsername) -or ($ProxyPassword) -or ($ResetProxy -eq $True) -or ($DetectProxy -eq $True)))
        ) {Write-Error "ERROR: Line $(LINENUM): Set-LTProxy: Invalid Parameter specified" -ErrorAction Stop}
        If (-not (($ResetProxy -eq $True) -or ($DetectProxy -eq $True) -or ($ProxyServerURL) -or ($ProxyUsername) -or ($ProxyPassword) -or ($EncodedProxyUsername) -or ($EncodedProxyPassword)))
        {
            If ($Args.Count -gt 0) {Write-Error "ERROR: Line $(LINENUM): Set-LTProxy: Unknown Parameter specified" -ErrorAction Stop}
            Else {Write-Error "ERROR: Line $(LINENUM): Set-LTProxy: Required Parameters Missing" -ErrorAction Stop}
        }

        Try{
            If ($($ResetProxy) -eq $True) {
                Write-Verbose "ResetProxy selected. Clearing Proxy Settings."
                If ( $PSCmdlet.ShouldProcess("LTProxy", "Clear") ) {
                    $Script:LTProxy.Enabled=$False
                    $Script:LTProxy.ProxyServerURL=''
                    $Script:LTProxy.ProxyUsername=''
                    $Script:LTProxy.ProxyPassword=''
                    $Script:LTWebProxy=New-Object System.Net.WebProxy
                    $Script:LTServiceNetWebClient.Proxy=$Script:LTWebProxy
                }#End If
            } ElseIf ($($DetectProxy) -eq $True) {
                Write-Verbose "DetectProxy selected. Attempting to Detect Proxy Settings."
                If ( $PSCmdlet.ShouldProcess("LTProxy", "Detect") ) {
                    $Script:LTWebProxy=[System.Net.WebRequest]::GetSystemWebProxy()
                    $Script:LTProxy.Enabled=$False
                    $Script:LTProxy.ProxyServerURL=''
                    $Servers = @($("$($LTSS|Select-Object -Expand 'ServerAddress' -EA 0)|www.connectwise.com").Split('|')|ForEach-Object {$_.Trim()})
                    Foreach ($Svr In $Servers) {
                        If (-not ($Script:LTProxy.Enabled)) {
                            If ($Svr -match '^(https?://)?(([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}|[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*)$') {
                                $Svr = $Svr -replace 'https?://',''
                                Try{
                                    $Script:LTProxy.ProxyServerURL=$Script:LTWebProxy.GetProxy("http://$($Svr)").Authority
                                } catch {}
                                If (($Null -ne $Script:LTProxy.ProxyServerURL) -and ($Script:LTProxy.ProxyServerURL -ne '') -and ($Script:LTProxy.ProxyServerURL -notcontains "$($Svr)")) {
                                    Write-Debug "Line $(LINENUM): Detected Proxy URL: $($Script:LTProxy.ProxyServerURL) on server $($Svr)"
                                    $Script:LTProxy.Enabled=$True
                                }#End If
                            }#End If
                        }#End If
                    }#End Foreach
                    If (-not ($Script:LTProxy.Enabled)) {
                        if (($Script:LTProxy.ProxyServerURL -eq '') -or ($Script:LTProxy.ProxyServerURL -contains '$Svr')) {
                            $Script:LTProxy.ProxyServerURL = netsh winhttp show proxy | select-string -pattern '(?i)(?<=Proxyserver.*http\=)([^;\r\n]*)' -EA 0|ForEach-Object {$_.matches}|Select-Object -Expand value
                        }
                        if (($Null -eq $Script:LTProxy.ProxyServerURL) -or ($Script:LTProxy.ProxyServerURL -eq '')) {
                            $Script:LTProxy.ProxyServerURL=''
                            $Script:LTProxy.Enabled=$False
                        } else {
                            $Script:LTProxy.Enabled=$True
                            Write-Debug "Line $(LINENUM): Detected Proxy URL: $($Script:LTProxy.ProxyServerURL)"
                        }
                    }#End If
                    $Script:LTProxy.ProxyUsername=''
                    $Script:LTProxy.ProxyPassword=''
                    $Script:LTServiceNetWebClient.Proxy=$Script:LTWebProxy
                }#End If
            } ElseIf (($ProxyServerURL)) {
                If ( $PSCmdlet.ShouldProcess("LTProxy", "Set") ) {
                    foreach ($ProxyURL in $ProxyServerURL) {
                        $Script:LTWebProxy = New-Object System.Net.WebProxy($ProxyURL, $true);
                        $Script:LTProxy.Enabled=$True
                        $Script:LTProxy.ProxyServerURL=$ProxyURL
                    }
                    Write-Verbose "Setting Proxy URL to: $($ProxyServerURL)"
                    If ((($ProxyUsername) -and ($ProxyPassword)) -or (($EncodedProxyUsername) -and ($EncodedProxyPassword))) {
                        If (($ProxyUsername)) {
                            foreach ($proxyUser in $ProxyUsername) {
                                $Script:LTProxy.ProxyUsername=$proxyUser
                            }
                        }
                        If (($EncodedProxyUsername)) {
                            foreach ($proxyUser in $EncodedProxyUsername) {
                                $Script:LTProxy.ProxyUsername=$(ConvertFrom-LTSecurity -InputString "$($proxyUser)" -Key ("$($Script:LTServiceKeys.PasswordString)",''))
                            }
                        }
                        If (($ProxyPassword)) {
                            foreach ($proxyPass in $ProxyPassword) {
                                $Script:LTProxy.ProxyPassword=$proxyPass
                                $passwd = ConvertTo-SecureString $proxyPass -AsPlainText -Force; ## Website credentials
                            }
                        }
                        If (($EncodedProxyPassword)) {
                            foreach ($proxyPass in $EncodedProxyPassword) {
                                $Script:LTProxy.ProxyPassword=$(ConvertFrom-LTSecurity -InputString "$($proxyPass)" -Key ("$($Script:LTServiceKeys.PasswordString)",''))
                                $passwd = ConvertTo-SecureString $Script:LTProxy.ProxyPassword -AsPlainText -Force; ## Website credentials
                            }
                        }
                        $Script:LTWebProxy.Credentials = New-Object System.Management.Automation.PSCredential ($Script:LTProxy.ProxyUsername, $passwd);
                    }#End If
                    $Script:LTServiceNetWebClient.Proxy=$Script:LTWebProxy
                }#End If
            }#End If
        }#End Try

        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was an error during the Proxy Configuration process. $($Error[0])" -ErrorAction Stop
        }#End Catch
    }#End Process

    End{
        If ($?){
            $LTServiceSettingsChanged=$False
            If ($Null -ne ($LTSS)) {
                If (($LTSS|Get-Member|Where-Object {$_.Name -eq 'ProxyServerURL'})) {
                    If (($($LTSS|Select-Object -Expand ProxyServerURL -EA 0) -replace 'https?://','' -ne $Script:LTProxy.ProxyServerURL) -and (($($LTSS|Select-Object -Expand ProxyServerURL -EA 0) -replace 'https?://','' -eq '' -and $Script:LTProxy.Enabled -eq $True -and $Script:LTProxy.ProxyServerURL -match '.+\..+') -or ($($LTSS|Select-Object -Expand ProxyServerURL -EA 0) -replace 'https?://','' -ne '' -and ($Script:LTProxy.ProxyServerURL -ne '' -or $Script:LTProxy.Enabled -eq $False)))) {
                        Write-Debug "Line $(LINENUM): ProxyServerURL Changed: Old Value: $($LTSS|Select-Object -Expand ProxyServerURL -EA 0) New Value: $($Script:LTProxy.ProxyServerURL)"
                        $LTServiceSettingsChanged=$True
                    }#End If
                    If (($LTSS|Get-Member|Where-Object {$_.Name -eq 'ProxyUsername'}) -and ($LTSS|Select-Object -Expand ProxyUsername -EA 0)) {
                        If ($(ConvertFrom-LTSecurity -InputString "$($LTSS|Select-Object -Expand ProxyUsername -EA 0)" -Key ("$($Script:LTServiceKeys.PasswordString)",'')) -ne $Script:LTProxy.ProxyUsername) {
                            Write-Debug "Line $(LINENUM): ProxyUsername Changed: Old Value: $(ConvertFrom-LTSecurity -InputString "$($LTSS|Select-Object -Expand ProxyUsername -EA 0)" -Key ("$($Script:LTServiceKeys.PasswordString)",'')) New Value: $($Script:LTProxy.ProxyUsername)"
                            $LTServiceSettingsChanged=$True
                        }
                    }#End If
                    If ($Null -ne ($LTSS) -and ($LTSS|Get-Member|Where-Object {$_.Name -eq 'ProxyPassword'}) -and ($LTSS|Select-Object -Expand ProxyPassword -EA 0)) {
                        If ($(ConvertFrom-LTSecurity -InputString "$($LTSS|Select-Object -Expand ProxyPassword -EA 0)" -Key ("$($Script:LTServiceKeys.PasswordString)",'')) -ne $Script:LTProxy.ProxyPassword) {
                            Write-Debug "Line $(LINENUM): ProxyPassword Changed: Old Value: $(ConvertFrom-LTSecurity -InputString "$($LTSS|Select-Object -Expand ProxyPassword -EA 0)" -Key ("$($Script:LTServiceKeys.PasswordString)",'')) New Value: $($Script:LTProxy.ProxyPassword)"
                            $LTServiceSettingsChanged=$True
                        }
                    }#End If
                } ElseIf ($Script:LTProxy.Enabled -eq $True -and $Script:LTProxy.ProxyServerURL -match '(https?://)?.+\..+') {
                    Write-Debug "Line $(LINENUM): ProxyServerURL Changed: Old Value: NOT SET New Value: $($Script:LTProxy.ProxyServerURL)"
                    $LTServiceSettingsChanged=$True
                }#End If
            } Else {
                $svcRun = ('LTService') | Get-Service -EA 0 | Where-Object {$_.Status -eq 'Running'} | Measure-Object | Select-Object -Expand Count
                if (($svcRun -gt 0) -and ($($Script:LTProxy.ProxyServerURL) -match '.+')) {
                    $LTServiceSettingsChanged=$True
                }#End If
            }#End If
            If ($LTServiceSettingsChanged -eq $True) {
                If ((Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue|Where-Object {$_.Status -match 'Running'})) { $LTServiceRestartNeeded=$True; try {Stop-LTService -EA 0 -WA 0} catch {} }
                Write-Verbose "Updating LabTech\Service\Settings Proxy Configuration."
                If ( $PSCmdlet.ShouldProcess("LTService Registry", "Update") ) {
                    $Svr=$($Script:LTProxy.ProxyServerURL); If (($Svr -ne '') -and ($Svr -notmatch 'https?://')) {$Svr = "http://$($Svr)"}
                    @{"ProxyServerURL"=$Svr;
                    "ProxyUserName"="$(ConvertTo-LTSecurity -InputString "$($Script:LTProxy.ProxyUserName)" -Key "$($Script:LTServiceKeys.PasswordString)")";
                    "ProxyPassword"="$(ConvertTo-LTSecurity -InputString "$($Script:LTProxy.ProxyPassword)" -Key "$($Script:LTServiceKeys.PasswordString)")"}.GetEnumerator() | Foreach-Object {
                        Write-Debug "Line $(LINENUM): Setting Registry value for $($_.Name) to `"$($_.Value)`""
                        Set-ItemProperty -Path 'HKLM:Software\LabTech\Service\Settings' -Name $($_.Name) -Value $($_.Value) -EA 0 -Confirm:$False
                    }#End Foreach-Object
                }#End If
                If ($LTServiceRestartNeeded -eq $True) { try {Start-LTService -EA 0 -WA 0} catch {} }
            }#End If
        }#End If
        Else {$Error[0]}
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
    }#End End

}#End Function Set-LTProxy

Function Get-LTProxy{
<#
.SYNOPSIS
    This function retrieves the current agent proxy settings for module functions
    to use the specified proxy configuration for all communication operations as
    long as the module remains loaded.

.DESCRIPTION
    This function will get the current LabTech Proxy settings from the
    installed agent (if present). If no agent settings are found, the function
    will attempt to discover the current proxy settings for the system.
    The Proxy Settings determined will be stored in memory for internal use, and
    returned as the function result.

.NOTES
    Version:        1.1
    Author:         Darren White
    Creation Date:  1/24/2018
    Purpose/Change: Initial function development

    Update Date: 3/18/2018
    Purpose/Change: Ensure ProxyUser and ProxyPassword are set correctly when proxy
    is not configured.

.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param(
    )

    Begin{
        Clear-Variable CustomProxyObject,LTSI,LTSS -EA 0 -WhatIf:$False -Confirm:$False #Clearing Variables for use
        Write-Debug "Starting $($myInvocation.InvocationName) at line $(LINENUM)"
        Write-Verbose "Discovering Proxy Settings used by the LT Agent."
        $Null=Initialize-LTServiceKeys
    }#End Begin

    Process{
        Try {
            $LTSI=Get-LTServiceInfo -EA 0 -WA 0 -Verbose:$False -WhatIf:$False -Confirm:$False -Debug:$False
            If ($Null -ne $LTSI -and ($LTSI|Get-Member|Where-Object {$_.Name -eq 'ServerPassword'})) {
                $LTSS=Get-LTServiceSettings -EA 0 -Verbose:$False -WA 0 -Debug:$False
                If ($Null -ne $LTSS) {
                    If (($LTSS|Get-Member|Where-Object {$_.Name -eq 'ProxyServerURL'}) -and ($($LTSS|Select-Object -Expand ProxyServerURL -EA 0) -Match 'https?://.+')) {
                        Write-Debug "Line $(LINENUM): Proxy Detected. Setting ProxyServerURL to $($LTSS|Select-Object -Expand ProxyServerURL -EA 0)"
                        $Script:LTProxy.Enabled=$True
                        $Script:LTProxy.ProxyServerURL="$($LTSS|Select-Object -Expand ProxyServerURL -EA 0)"
                    } Else {
                        Write-Debug "Line $(LINENUM): Setting ProxyServerURL to "
                        $Script:LTProxy.Enabled=$False
                        $Script:LTProxy.ProxyServerURL=''
                    }#End If
                    if ($Script:LTProxy.Enabled -eq $True -and ($LTSS|Get-Member|Where-Object {$_.Name -eq 'ProxyUsername'}) -and ($LTSS|Select-Object -Expand ProxyUsername -EA 0)) {
                        $Script:LTProxy.ProxyUsername="$(ConvertFrom-LTSecurity -InputString "$($LTSS|Select-Object -Expand ProxyUsername -EA 0)" -Key ("$($Script:LTServiceKeys.PasswordString)",''))"
                        Write-Debug "Line $(LINENUM): Setting ProxyUsername to $($Script:LTProxy.ProxyUsername)"
                    } Else {
                        Write-Debug "Line $(LINENUM): Setting ProxyUsername to "
                        $Script:LTProxy.ProxyUsername=''
                    }#End If
                    If ($Script:LTProxy.Enabled -eq $True -and ($LTSS|Get-Member|Where-Object {$_.Name -eq 'ProxyPassword'}) -and ($LTSS|Select-Object -Expand ProxyPassword -EA 0)) {
                        $Script:LTProxy.ProxyPassword="$(ConvertFrom-LTSecurity -InputString "$($LTSS|Select-Object -Expand ProxyPassword -EA 0)" -Key ("$($Script:LTServiceKeys.PasswordString)",''))"
                        Write-Debug "Line $(LINENUM): Setting ProxyPassword to $($Script:LTProxy.ProxyPassword)"
                    } Else {
                        Write-Debug "Line $(LINENUM): Setting ProxyPassword to "
                        $Script:LTProxy.ProxyPassword=''
                    }#End If
                }#End If
            } Else {
                Write-Verbose "No Server password or settings exist. No Proxy information will be available."
            }#End If
        }#End Try
        Catch{
            Write-Error "ERROR: Line $(LINENUM): There was a problem retrieving Proxy Information. $($Error[0])"
        }#End Catch
    }#End Process

    End{
        Write-Debug "Exiting $($myInvocation.InvocationName) at line $(LINENUM)"
        return $Script:LTProxy
    }#End End
}#End Function Get-LTProxy

Function Get-CurrentLineNumber {
    $MyInvocation.ScriptLineNumber
}
Set-Alias -name LINENUM -value Get-CurrentLineNumber -WhatIf:$False -Confirm:$False -Scope Script

Function Initialize-LTServiceModule{
<#
.SYNOPSIS
    This function initializes internal variables needed by other functions

.DESCRIPTION
    This function will set variables for the Agent and Server passwords needed
    for encoding and decoding steps.

.NOTES
    Version:        1.1
    Author:         Darren White
    Creation Date:  1/25/2018
    Purpose/Change: Initial function development

    Update Date: 3/18/2018
    Purpose/Change: Rename to Initialize-LTServiceKeys

.LINK
    http://labtechconsulting.com
#>

    #Populate $Script:LTServiceKeys Object
    $Script:LTServiceKeys = New-Object -TypeName PSObject
    Add-Member -InputObject $Script:LTServiceKeys -MemberType NoteProperty -Name ServerPasswordString -Value ''
    Add-Member -InputObject $Script:LTServiceKeys -MemberType NoteProperty -Name PasswordString -Value ''

    #Populate $Script:LTProxy Object
    Try{
        $Script:LTProxy = New-Object -TypeName PSObject
        Add-Member -InputObject $Script:LTProxy -MemberType NoteProperty -Name ProxyServerURL -Value ''
        Add-Member -InputObject $Script:LTProxy -MemberType NoteProperty -Name ProxyUsername -Value ''
        Add-Member -InputObject $Script:LTProxy -MemberType NoteProperty -Name ProxyPassword -Value ''
        Add-Member -InputObject $Script:LTProxy -MemberType NoteProperty -Name Enabled -Value ''

        #Populate $Script:LTWebProxy Object
        $Script:LTWebProxy=new-object System.Net.WebProxy

        #Initialize $Script:LTServiceNetWebClient Object
        $Script:LTServiceNetWebClient = New-Object System.Net.WebClient
        $Script:LTServiceNetWebClient.Proxy=$Script:LTWebProxy
    } Catch {
        Write-Error "ERROR: Line $(LINENUM): Failed Initializing internal Proxy Objects/Variables."
    }

    $Null=Get-LTProxy -ErrorAction Continue

}#End Initialize-LTServiceModule

#endregion Functions

$PublicFunctions=@(((@"
ConvertFrom-LTSecurity
ConvertTo-LTSecurity
Get-LTErrors
Get-LTLogging
Get-LTProbeErrors
Get-LTProxy
Get-LTServiceInfo
Get-LTServiceInfoBackup
Get-LTServiceSettings
Hide-LTAddRemove
Install-LTService
Invoke-LTServiceCommand
New-LTServiceBackup
Redo-LTService
Rename-LTAddRemove
Reset-LTService
Restart-LTService
Set-LTLogging
Set-LTProxy
Show-LTAddRemove
Start-LTService
Stop-LTService
Test-LTPorts
Uninstall-LTService
Update-LTService
"@) -replace "[`r`n,\s]+",',') -split ',')

$PublicAlias=@(((@"
Get-LTError
ReInstall-LTService
"@) -replace "[`r`n,\s]+",',') -split ',')

If (($MyInvocation.Line -match 'Import-Module' -or $MyInvocation.MyCommand -match 'Import-Module') -and -not ($MyInvocation.Line -match $ModuleGuid -or $MyInvocation.MyCommand -match $ModuleGuid)) {
    # Only export module members when being loaded as a module
    Export-ModuleMember -Function $PublicFunctions -Alias $PublicAlias -EA 0 -WA 0

<#
'Just a small code block to use when developing new features to ensure new functions are not missed.
'Here just so that I don't need to track it down when I want it. - DJW
    $UnPublicFunctions=(Get-Content 'Script Source' | Select-String -Pattern '(?<=^function )[-\w]+' -AllMatches | Select-Object -expand matches) | ForEach-Object {if ($PublicFunctions -notcontains $_.value) {$_.value}};
    if ($UnPublicFunctions) {Write-Debug "Not publishing functions: $(($UnPublicFunctions) -join ',')"}
#>
}

$Null=Initialize-LTServiceModule

#SneakyRun - Save as FUNCTION.ps1 and call FUNCTION.ps1, and it will be treated as if you called FUNCTION directly.
#Maybe it's not that special. You can dot-source the script and call any function directly.  
#Example: Name it "Install-LTService.ps1", then you can call it as the file and it will run that function.
if ($PSCommandPath -like '*.ps1' -and $PSCommandPath -like "*$($MyInvocation.MyCommand)") {
    $LabTechFunction=$MyInvocation.MyCommand.ToString() -replace '\.ps1',''
    If ($PublicFunctions -contains $LabTechFunction) {
        Write-Debug "Script Name $LabTechFunction.ps1 matches a defined function. Calling $LabTechFunction $($args|ConvertTo-JSON -Depth 1 -Compress)"
        & $LabTechFunction @args
    } Else {
        Write-Debug "Script Name $LabTechFunction.ps1 does not match a defined function for this module."
    }
}
