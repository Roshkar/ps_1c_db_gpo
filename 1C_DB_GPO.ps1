<#
Скрипт распространения БД 1С в зависимости от принадлежности авторизованного пользователя к группе Active Directory
Возможно распространения средствами групповых политик
Пример запуска скрипта вручную


<# Параметр, принимающий значение пути к ini-файлу конфигурации #>
param([Parameter()]
     [string]$config
 )

<# VARIABLES #>

<# расположение каталога установки 1С версии 8.2.
Архитектура x86 #>
$1C82AppLocationX86 = "C:\Program Files (x86)\1cv82"

<# расположение каталога установки 1С версии 8.3.
Архитектура x86 #>
$1C83AppLocationX86 = "C:\Program Files (x86)\1cv8"

<# расположение каталога установки 1С версии 8.2.
Архитектура x64 #>
$1C82AppLocationX64 = "C:\Program Files\1cv82"

<# расположение каталога установки 1С версии 8.3.
Архитектура x64 #>
$1C83AppLocationX64 = "C:\Program Files\1cv8"

<# Каталог файла 1CEStart.cfg #>
$1CEStartLocation = "$($env:APPDATA)\1C\1CEStart"

<# Файл 1CEStart.cfg #>
$1CEStartFileName = "1CEStart.cfg"

<# END VARIABLES #>

<# FUNCTIONS #>

<# Получение содержимого ini-файла конфигурации #>
function Get-IniFile 
{  
    param(  
        [parameter(Mandatory = $true)] [string] $filePath  
    )  
    
    $anonymous = "NoSection"
  
    $ini = @{}  
    switch -regex -file $filePath  
    {  
        "^\[(.+)\]$" # Section  
        {  
            $section = $matches[1]  
            $ini[$section] = @{}  
            $CommentCount = 0  
        }  

        "^(;.*)$" # Comment  
        {  
            if (!($section))  
            {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $value = $matches[1]  
            $CommentCount = $CommentCount + 1  
            $name = "Comment" + $CommentCount  
            $ini[$section][$name] = $value  
        }   

        "(.+?)\s*=\s*(.*)" # Key  
        {  
            if (!($section))  
            {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $name,$value = $matches[1..2]  
            $ini[$section][$name] = $value  
        }  
    }  

    return $ini  
}

<# Ведение файла журнала #>
function Write-Log {
    Param(
        $Message,
        $Path = "1c_db_gpo_log.txt"
    )

    function TS {
        Get-Date -Format 'hh:mm:ss'
    }
    Write-Output "[$(TS)]$Message" 
    Write-Output "[$(TS)]$Message" | Out-File $Path -Append
}

<# END FUNCTIONS #>

<# SETUP PARAMETERS #>

<# Установка файла конфигурации.
Если параметр config не указан, скрипт будет искать файл config.ini в директории текущего расположения #>
if ([string]::IsNullOrEmpty($config)) {
    $ini = "config.ini"
    $ConfFile = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    $ini = $ConfFile + "\" + $ini
} else {
    $ini = $config
}

$iniFile = Get-IniFile $ini

<# Путь к файлу csv, содержащему данные о пользователях#>
$CsvPath = $iniFile.csv.file

<# Разделитель значений файла csv #>
$CsvDelimiter = $iniFile.csv.delimiter

<# Название столбца, содержащего группы пользователей Active Directory #>
$GroupHeader = $iniFile.csv.groupheader

<# Название столбца, содержащего пути к файлам конфигруации БД 1С #>
$ConfigFileHeader = $iniFile.csv.configfileheader


Write-Log $CsvPath

<# Текущий пользователь #>
$User = $env:username

Write-Log $User

<# Полный путь к файлу 1CEStart.cfg в каталоге %APPDATA% #>
$1CEStartPath = $1CEStartLocation + "\" + $1CEStartFileName

Write-Log $1CEStartPath

<# END SETUP PARAMETERS #>

<# VALIDATION #>

if ((! (Test-Path $1C83AppLocationX86 -PathType Container -ErrorAction SilentlyContinue)) -and (! (Test-Path $1C82AppLocationX86 -PathType Container -ErrorAction SilentlyContinue)) `
-and (! (Test-Path $1C82AppLocationX64 -PathType Container -ErrorAction SilentlyContinue)) -and (! (Test-Path $1C83AppLocationX64 -PathType Container -ErrorAction SilentlyContinue)))
{
    
    Write-Log "1C Application does not installed"
    
    Break
}

<# Создать каталог 1CEStart в каталоге %APPDATA% в случае отсутствия #>
if (! (Test-Path $1CEStartLocation -PathType Container -ErrorAction SilentlyContinue)) {
    New-Item $1CEStartLocation -ItemType D -Force
    
    Write-Log "$1CEStartLocation was created"

} else {
    
    Write-Log "$1CEStartLocation exist. Continue"

}

<# END VALIDATION #>

<# Получение содержимого csv-файла #>
$BaseCsv = Get-Content $CsvPath | ConvertFrom-Csv -delimiter $CsvDelimiter

Write-Log $BaseCsv

<# Получение групп пользователей #>
$GroupsArray = $BaseCsv | Select-Object -Expand $GroupHeader

Write-Log $GroupsArray

<# Результирующий массив баз данных пользователя #>
$ResultDbArray = @()

foreach ($Group in $GroupsArray) {
    $ADGroupObj = ([ADSISEARCHER]"samaccountname=$($env:USERNAME)").Findone().Properties.memberof -replace '^CN=([^,]+).+$','$1' -like $Group
    if ($ADGroupObj -and $ADGroupObj.count -gt 0)
   {
      $ResultDbArray += $BaseCsv | Where-Object {$_.$GroupHeader -eq $Group}
   }
}


#foreach ($Group in $GroupsArray) {
#    $ADGroupObj = [ADSISearcher] ('(&(objectCategory=person)(objectClass=user)(sAMAccountName=$user))').FindOne().properties.memberof -match "$Group"
#    if ($ADGroupObj -and $ADGroupObj.count -gt 0)
#    {
#       $ResultDbArray += $BaseCsv | Where-Object {$_.$GroupHeader -eq $Group}
#   }
#}

Write-Log $ResultDbArray

<# Получение путей к файлам конфигурации БД 1С #>
$BasesConfig = $ResultDbArray | Select-Object -Expand $ConfigFileHeader

Write-Log $BasesConfig

<# Генерация строки подключения файлов конфигурации БД 1С #>
$Result = @()
foreach ($config in $BasesConfig) {
    $Result += "CommonInfoBases="+$config
}

Write-Log $Result

<# Сохранение в каталог пользователя %APPDATA% #>
$Result | Out-File -FilePath $1CEStartPath
