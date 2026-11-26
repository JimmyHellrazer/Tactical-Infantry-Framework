import bpy

# Define the mapping of old bone names to new bone names here
# Add new entries as needed in the format: 'old_bone_name': 'new_bone_name'
bone_mapping = {
    # Spine
    'j_mainroot': 'ValveBiped.Bip01_Pelvis',
    'j_spinelower': 'ValveBiped.Bip01_Spine1',
    'j_spineupper': 'ValveBiped.Bip01_Spine2',
    'j_spine4': 'ValveBiped.Bip01_Spine4',
    'j_neck': 'ValveBiped.Bip01_Neck1',
    'j_head': 'ValveBiped.Bip01_Head1',
    'j_visor_inner': 'j_headset',
    'j_visor': 'j_hat',
    'tag_eye': 'j_eyewear',
    # Legs
    'j_hip_le': 'ValveBiped.Bip01_L_Thigh',
    'j_hiptwist_le': 'ValveBiped.Bip01_L_Quadricep',
    'j_hip_proc_le': 'ValveBiped.Bip01_L_Quadricep2',
    'j_knee_le': 'ValveBiped.Bip01_L_Calf',
    'j_ankle_le': 'ValveBiped.Bip01_L_Foot',
    'j_ball_le': 'ValveBiped.Bip01_L_Toe0',
    'j_hip_ri': 'ValveBiped.Bip01_R_Thigh',
    'j_hiptwist_ri': 'ValveBiped.Bip01_R_Quadricep',
    'j_hip_proc_ri': 'ValveBiped.Bip01_R_Quadricep2',
    'j_knee_ri': 'ValveBiped.Bip01_R_Calf',
    'j_ankle_ri': 'ValveBiped.Bip01_R_Foot',
    'j_ball_ri': 'ValveBiped.Bip01_R_Toe0',
    # Left arm
    'j_clavicle_le': 'ValveBiped.Bip01_L_Clavicle',
    'j_shoulder_le': 'ValveBiped.Bip01_L_UpperArm',
    'j_shouldertwist_le': 'ValveBiped.Bip01_L_Shoulder',
    'j_elbow_le': 'ValveBiped.Bip01_L_Forearm',
    'j_wristfronttwist1_le': 'ValveBiped.Bip01_L_Wrist',
    'j_wrist_le': 'ValveBiped.Bip01_L_Hand',
    'j_thumb_le_1': 'ValveBiped.Bip01_L_Finger0',
    'j_thumb_le_2': 'ValveBiped.Bip01_L_Finger01',
    'j_thumb_le_3': 'ValveBiped.Bip01_L_Finger02',
    'j_metaindex_le_1': 'ValveBiped.Bip01_L_Finger10',
    'j_index_le_1': 'ValveBiped.Bip01_L_Finger1',
    'j_index_le_2': 'ValveBiped.Bip01_L_Finger11',
    'j_index_le_3': 'ValveBiped.Bip01_L_Finger12',
    'j_metamid_le_1': 'ValveBiped.Bip01_L_Finger20',
    'j_mid_le_1': 'ValveBiped.Bip01_L_Finger2',
    'j_mid_le_2': 'ValveBiped.Bip01_L_Finger21',
    'j_mid_le_3': 'ValveBiped.Bip01_L_Finger22',
    'j_metaring_le_1': 'ValveBiped.Bip01_L_Finger30',
    'j_ring_le_1': 'ValveBiped.Bip01_L_Finger3',
    'j_ring_le_2': 'ValveBiped.Bip01_L_Finger31',
    'j_ring_le_3': 'ValveBiped.Bip01_L_Finger32',
    'j_metapinky_le_1': 'ValveBiped.Bip01_L_Finger40',
    'j_pinky_le_1': 'ValveBiped.Bip01_L_Finger4',
    'j_pinky_le_2': 'ValveBiped.Bip01_L_Finger41',
    'j_pinky_le_3': 'ValveBiped.Bip01_L_Finger42',
    # Right arm
    'j_clavicle_ri': 'ValveBiped.Bip01_R_Clavicle',
    'j_shoulder_ri': 'ValveBiped.Bip01_R_UpperArm',
    'j_shouldertwist_ri': 'ValveBiped.Bip01_R_Shoulder',
    'j_elbow_ri': 'ValveBiped.Bip01_R_Forearm',
    'j_wristfronttwist1_ri': 'ValveBiped.Bip01_R_Wrist',
    'j_wrist_ri': 'ValveBiped.Bip01_R_Hand',
    'j_thumb_ri_1': 'ValveBiped.Bip01_R_Finger0',
    'j_thumb_ri_2': 'ValveBiped.Bip01_R_Finger01',
    'j_thumb_ri_3': 'ValveBiped.Bip01_R_Finger02',
    'j_metaindex_ri_1': 'ValveBiped.Bip01_R_Finger10',
    'j_index_ri_1': 'ValveBiped.Bip01_R_Finger1',
    'j_index_ri_2': 'ValveBiped.Bip01_R_Finger11',
    'j_index_ri_3': 'ValveBiped.Bip01_R_Finger12',
    'j_metamid_ri_1': 'ValveBiped.Bip01_R_Finger20',
    'j_mid_ri_1': 'ValveBiped.Bip01_R_Finger2',
    'j_mid_ri_2': 'ValveBiped.Bip01_R_Finger21',
    'j_mid_ri_3': 'ValveBiped.Bip01_R_Finger22',
    'j_metaring_ri_1': 'ValveBiped.Bip01_R_Finger30',
    'j_ring_ri_1': 'ValveBiped.Bip01_R_Finger3',
    'j_ring_ri_2': 'ValveBiped.Bip01_R_Finger31',
    'j_ring_ri_3': 'ValveBiped.Bip01_R_Finger32',
    'j_metapinky_ri_1': 'ValveBiped.Bip01_R_Finger40',
    'j_pinky_ri_1': 'ValveBiped.Bip01_R_Finger4',
    'j_pinky_ri_2': 'ValveBiped.Bip01_R_Finger41',
    'j_pinky_ri_3': 'ValveBiped.Bip01_R_Finger42',
}

def rename_bones():
    # Get the active armature in the current scene
    armature = bpy.context.object
    if armature.type != 'ARMATURE':
        print("Selected object is not an armature.")
        return

    # Ensure we are in pose mode
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode='POSE')

    # Rename the bones based on the mapping dictionary
    for old_name, new_name in bone_mapping.items():
        if old_name in armature.pose.bones:
            armature.pose.bones[old_name].name = new_name
            print(f"Renamed {old_name} to {new_name}.")
        else:
            print(f"{old_name} bone not found in the armature. Skipping...")

    bpy.ops.object.mode_set(mode='OBJECT')  # Switch back to object mode

# Call the function to rename the bones
rename_bones()