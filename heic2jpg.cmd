@echo off

rem heic 2 jpg
rem %1 - heic photo file
rem output - jpeg 100% quality autorotated photo file, same name

setlocal enableextensions
setlocal enabledelayedexpansion

cd "%~dp0"

rem tools variables

rem http://gnuwin32.sourceforge.net/
set grep=grep -q -s -e
set sed=sed -u -n -r

rem https://ffmpeg.org/
set ffmpeg=ffmpeg.exe -nostdin -loglevel quiet -hide_banner -y

rem https://gpac.wp.imt.fr/
set mp4box=gpac\mp4box -quiet

rem https://exiftool.org/
set exiftool=exiftool.exe -q -q -m -fast -S -ee

rem https://www.sentex.ca/~mwandel/jhead/
set jhead=jhead.exe -exonly -q -se

rem https://imagemagick.org/
set convert=convert.exe -quiet

call :HeicToJpg "%~1"
exit /b %errorlevel%

:HeicToJpg
rem %1 - heic file

rem prepare folder and xml data
set "workFolder=%~dpnx1.tmp"
if not exist "%workFolder%\" md "%workFolder%" >nul 2>nul
set "disoFile=%workFolder%\diso.xml"
%mp4box% -diso -out "%disoFile%" "%~1" || call :error %errorlevel% "Error handling diso info" || exit /b %errorlevel%

rem find primary item
set "primaryItem="
call :getPrimaryItem "%disoFile%" || call :getPrimaryGridItem "%disoFile%" || echo.Primary item not found && exit /b 1 
rem echo %primaryItem%

rem find size of primary item
call :getItemSize "%disoFile%" %primaryItem% || echo.Primary size not found && exit /b 1
rem echo %image_width%
rem echo %image_height%

rem save size
set /a primaryWidth=image_width
set /a primaryHeight=image_height

rem find grid items
set "gridItems="
call :getGridItems "%disoFile%" %primaryItem% || echo.Grid items not found && exit /b 1
rem echo %gridItems%

rem let grid items all are equal size
set /a rows=0
set /a cols=0
set /a max_width=0
set /a max_height=0

rem extract items and save list
set "listFile=%workFolder%\items.list"
echo >"%listFile%"
for %%i in (%gridItems%) do (
	rem echo Processing item %%i...
	%mp4box% -dump-item %%i:path="%workFolder%\item%%i.hevc" "%~1"
	echo file item%%i.hevc >>"%listFile%"
	call :getItemSize "%disoFile%" %%i && (
		if "%image_width%" GTR "%max_width%" set /a max_width=image_width
		if "%image_height%" GTR "%max_height%" set /a max_height=image_height
	)
)
if %max_width% GTR 0 set /a rows=primaryWidth / max_width , max_width=primaryWidth %% max_width
if %max_width% GTR 0 set /a rows+=1
if %max_height% GTR 0 set /a cols=primaryHeight / max_height , max_height=primaryHeight %% max_height
if %max_height% GTR 0 set /a cols+=1
rem echo %rows%
rem echo %cols%

rem remove first empty line
more +1 "%listFile%" > "%listFile%.new"
move /Y "%listFile%.new" "%listFile%" >nul 2>nul 
rem %sed% -i -c -e "1^!p" "%listFile%" >"%listFile%" 

rem concat
set "resultFile=%workFolder%\result.tiff"
if exist "%resultFile%" del /F /Q "%resultFile%" >nul 2>nul
pushd "%workFolder%"
%~dp0\%ffmpeg% -f concat -i "%listFile%" ^
-vf tile=%rows%x%cols%,crop=%primaryWidth%:%primaryHeight%:0:0 ^
-vframes 1 ^
-q:v 1 -qmin 1 ^
-compression_level 0 -qcomp 0 -lossless 1 ^
-an "%resultFile%"
if not exist "%resultFile%" echo.Error concatenating items && exit /b 1
popd

rem convert to jpg and set all
%convert% -quality 100 "%resultFile%" "%~dpn1.jpg"

rem now copy info from heic to jpg
rem copy icc profile, XMP MakerNotes EXIF
set "tagGroups="
call :getTagGroups "%~1" "-"
if errorlevel 1 set "tagGroups=-icc_profile -XMP -MakerNotes -EXIF"
%exiftool% -overwrite_original -TagsFromFile "%~1" %tagGroups% "-FileModifyDate" "-FileCreateDate" "%~dpn1.jpg" || exit /b %errorlevel%
%jhead% -autorot "%~dpn1.jpg"

rem try find thumbnail
set "thumbFile=%workFolder%\thumbnail"
if exist "%thumbFile%.jpg" del /F /Q "%thumbFile%.jpg" >nul 2>nul
set "thumbItem="
call :getThumbItem "%disoFile%" %primaryItem% && ^
%mp4box% -dump-item !thumbItem!:path="%thumbFile%.hevc" "%~1" && ^
%ffmpeg% -i "%thumbFile%.hevc" -frames:v 1 -q:v 1 -qmin 1 -qcomp 0 -an "%thumbFile%.jpg" && ^
%exiftool% -overwrite_original -TagsFromFile "%~1" -icc_profile -EXIF "-FileModifyDate" "-FileCreateDate" "%thumbFile%.jpg" && ^
%jhead% -autorot "%thumbFile%.jpg" && ^
%exiftool% -overwrite_original -ThumbnailImage^<="%thumbFile%.jpg" "%~dpn1.jpg"

rem finalize
%exiftool% -overwrite_original -TagsFromFile "%~1" "-FileModifyDate" "-FileCreateDate" "%~dpn1.jpg" || exit /b %errorlevel%

rem clean after
rem rmdir /S /Q "%workFolder%" >nul 2>nul

exit /b 0

:getPrimaryItem
set "primaryItem="
set "inplaceCommand=%sed% -e "/^<PrimaryItemBox.*^>/{s/.*item_ID=\"([0-9]+)\".*/\1/;p}" "%~1"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do set "primaryItem=%%i"
if "!primaryItem!"=="" exit /b 1
set "primaryItem=!primaryItem!"
exit /b 0

:getPrimaryGridItem
set "primaryItem="
set "inplaceCommand=%sed% -e "/^<ItemInfoEntryBox.*item_type=\"grid\".*^>/{s/.*item_ID=\"([0-9]+)\".*/\1/;p}" "%~1"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do set "primaryItem=%%i"
if "!primaryItem!"=="" exit /b 1
set "primaryItem=!primaryItem!"
exit /b 0

:getThumbItem
set "thumbItem="
set "inplaceCommand=%sed% -e "/^<ItemReferenceBox\s.*\"thmb\".*/,/^<\/ItemReferenceBox^>/{s/.*from_item_id=\"(\w+)\".*/\1/;ta;/^<ItemReferenceBoxEntry\s.*ItemID=\"%2\".*/{x;p;q};:a;h}" "%~1"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do set "thumbItem=%%i"
if "!thumbItem!"=="" exit /b 1
set "thumbItem=!thumbItem!"
exit /b 0

:getGridItems
rem %1 - diso file, %2 - primary item
set "gridItems="
set "inplaceCommand=%sed% -e "/^<ItemReferenceBox\s.*dimg.*from_item_id=\"%2\"/,/^<\/ItemReferenceBox^>/{s/^<ItemReferenceBoxEntry\s.*ItemID=\"([0-9]+)\".*/\1/p}" "%~1"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do set "gridItems=!gridItems! %%i"
if "!gridItems!"=="" exit /b 1
set "gridItems=!gridItems!"
exit /b 0

:dumpItems
if "%gridItems%"=="" exit /b 1
for %%i in (%gridItems%) do (
	%mp4box% -dump-item %%i:path="%~n1.item%%i.hevc" "%~1"
	%ffmpeg% -i "%~n1.item%%i.hevc" -frames:v 1 -q:v 1 -an "%~n1.item%%i.jpg"
)
exit /b 0

:getItemSize
rem %1 - diso file, %2 - item
set /a image_width=0
set /a image_height=0
set "propertyIndices="
call :getPropertyIndices "%~1" %2 || exit /b %errorlevel%
for %%i in (%propertyIndices%) do call :getProperties "%~1" ispe %%i
if "%image_width%"=="0" exit /b 1
if "%image_height%"=="0" exit /b 1
exit /b 0

:getPropertyIndices
rem %1 - diso file, %2 - item
set "propertyIndices="
set "inplaceCommand=%sed% -e "/^<AssociationEntry\s.*item_ID=\"%2\"/,/^<\/AssociationEntry^>/{s/^<Property\s.*index=\"([0-9]+)\".*/\1/p}" "%~1"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do set "propertyIndices=!propertyIndices! %%i"
if "!propertyIndices!"=="" exit /b 1
set "propertyIndices=!propertyIndices!"
exit /b 0

:getProperties
rem %1 - diso file, %2 - property name, %3 - property index
set "inplaceCommand=%sed% -e "/^<ItemPropertyContainerBox\s.*ipco.*/,/^<\/ItemPropertyContainerBox^>/{/^<.*Container=\".*ipco.*\"/p}" "%~1" | %sed% -e "%3{/=\"%2\"/{s/^^^<[[:alnum:]]+\s(.*)^>^$/\1/;s/\"\s/\"\n/g;s/\=\"/\=/gm;s/\"(\n^|^$)/\1/gm;s/^[A-Z].*^$\n//gm;p}}"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do if not "%%i"=="" call set "%%i"
exit /b 0

:getTagGroups
rem %1 - file %2 - delimiter
set "tagGroups="
set "inplaceCommand=%exiftool% -g "%~1" | %sed% -e "/----\s\w+\s----/s/----\s(\w+)\s----/\1/p" | grep -v -E -e "ExifTool^|File^|Composite^|QuickTime"" && ^
for /f "usebackq delims=" %%i in (`!inplaceCommand!`) do set "tagGroups=!tagGroups! %~2%%i"
if "!tagGroups!"=="" exit /b 1
set "tagGroups=!tagGroups!"
exit /b 0

:error
rem %1 exit code %2 - message
echo %~2 ^[error: %1^]
exit /b %1
