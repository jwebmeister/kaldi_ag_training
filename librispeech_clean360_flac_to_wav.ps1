$originalFlacs = Get-ChildItem -Path './LibriSpeech/train-clean-360' -Include '*.flac' -Recurse

foreach ($inputFlac in $originalFlacs) {
    $outputWav = [io.path]::ChangeExtension($inputFlac.FullName, '.wav')
    ffmpeg.exe -i $inputFlac.FullName $outputWav -y
    $inputFlac.Delete()
}