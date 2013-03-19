#!/bin/bash
set -e

if [ $# -eq 1 ]
	then
		echo "Version unknown..."
		exit 0
fi

SubjectID="$1" #FreeSurfer Subject ID Name
SubjectDIR="$2" #Location to Put FreeSurfer Subject's Folder
T1wImage="$3" #T1w FreeSurfer Input (Full Resolution)
T1wImageBrain="$4"
T2wImage="$5" #T2w FreeSurfer Input (Full Resolution)
PipelineScripts="$6"
PipelineBinaries="$7"
Caret5_Command="${8}"
Caret7_Command="${9}"
T1wImageFile=`remove_ext $T1wImage`;
T1wImageBrainFile=`remove_ext $T1wImageBrain`;

if [ -e "$SubjectDIR"/"$SubjectID"/scripts/IsRunning.lh+rh ] ; then
  rm "$SubjectDIR"/"$SubjectID"/scripts/IsRunning.lh+rh
fi

#Make Spline Interpolated Downsample to 1mm
Mean=`fslstats $T1wImageBrain -M`
flirt -interp spline -in "$T1wImage" -ref "$T1wImage" -applyisoxfm 1 -out "$T1wImageFile"_1mm.nii.gz
applywarp --rel --interp=spline -i "$T1wImage" -r "$T1wImageFile"_1mm.nii.gz --premat=$FSLDIR/etc/flirtsch/ident.mat -o "$T1wImageFile"_1mm.nii.gz
applywarp --rel --interp=nn -i "$T1wImageBrain" -r "$T1wImageFile"_1mm.nii.gz --premat=$FSLDIR/etc/flirtsch/ident.mat -o "$T1wImageBrainFile"_1mm.nii.gz
fslmaths "$T1wImageFile"_1mm.nii.gz -div $Mean -mul 150 -abs "$T1wImageFile"_1mm.nii.gz

#Initial Recon-all Steps
#-skullstrip of FreeSurfer not reliable for Phase II data because of poor FreeSurfer mri_em_register registrations with Skull on, run registration with PreFreeSurfer masked data and then generate brain mask as usual
#recon-all -i "$T1wImageFile"_1mm.nii.gz -subjid $SubjectID -sd $SubjectDIR -autorecon1 -autorecon2 -nosmooth2 -noinflate2
recon-all -i "$T1wImageFile"_1mm.nii.gz -subjid $SubjectID -sd $SubjectDIR -motioncor -talairach -nuintensitycor -normalization
mri_convert "$T1wImageBrainFile"_1mm.nii.gz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz --conform
mri_em_register -mask "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz "$SubjectDIR"/"$SubjectID"/mri/nu.mgz $FREESURFER_HOME/average/RB_all_2008-03-26.gca "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta
mri_watershed -T1 -brain_atlas $FREESURFER_HOME/average/RB_all_withskull_2008-03-26.gca "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta "$SubjectDIR"/"$SubjectID"/mri/T1.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.auto.mgz 
cp "$SubjectDIR"/"$SubjectID"/mri/brainmask.auto.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz 
recon-all -subjid $SubjectID -sd $SubjectDIR -autorecon2 -nosmooth2 -noinflate2

#Highres white stuff and Fine Tune T2w to T1w Reg
"$PipelineScripts"/FreeSurferHiresWhite.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage" "$PipelineBinaries" 

#Intermediate Recon-all Steps
recon-all -subjid $SubjectID -sd $SubjectDIR -smooth2 -inflate2 -sphere -surfreg -jacobian_white -avgcurv -cortparc 
#Highres pial stuff (this module will adjust the pial surface based on the the T2w image in the future)
#echo ""$PipelineScripts"/FreeSurferHiresPial.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage" "$PipelineBinaries" "$Caret5_Command" "$Caret7_Command""
"$PipelineScripts"/FreeSurferHiresPial.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage" "$PipelineBinaries" "$Caret5_Command" "$Caret7_Command"

#Final Recon-all Steps
recon-all -subjid $SubjectID -sd $SubjectDIR -surfvolume -parcstats -cortparc2 -parcstats2 -cortribbon -segstats -aparc2aseg -wmparc -balabels -label-exvivo-ec 


