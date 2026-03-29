#!/bin/bash
# patch_face_tracking.sh
# Run this after every Unity export to fix the FaceProvider linker errors.
# Works on both BetterVersion locations.

PATCH='
extern "C" {
    void* UnityARKit_FaceProvider_AcquireChanges(void** a, int32_t* ac, void** u, int32_t* uc, void** r, int32_t* rc, int32_t* max) { 
        if (ac) *ac = 0; 
        if (uc) *uc = 0; 
        if (rc) *rc = 0; 
        if (max) *max = 0; 
        return nullptr; 
    }
    void* UnityARKit_FaceProvider_AcquireFaceAnchor(TrackableId_t49EAE8AA4B9584E314518723DC22B66496D47AD7, void**, void**, int32_t*, void**, int32_t*) { return nullptr; }
    void UnityARKit_FaceProvider_DeallocateTempMemory(intptr_t) {}
    int32_t UnityARKit_FaceProvider_GetMaximumFaceCount() { return 0; }
    int32_t UnityARKit_FaceProvider_GetRequestedMaximumFaceCount() { return 0; }
    int32_t UnityARKit_FaceProvider_GetSupportedFaceCount() { return 0; }
    void UnityARKit_FaceProvider_Initialize() {}
    int32_t UnityARKit_FaceProvider_IsEyeTrackingSupported() { return 0; }
    int32_t UnityARKit_FaceProvider_IsSupported() { return 0; }
    void UnityARKit_FaceProvider_OnRegisterDescriptor() {}
    void UnityARKit_FaceProvider_ReleaseChanges(void*) {}
    void UnityARKit_FaceProvider_ReleaseFaceAnchor(void*) {}
    void UnityARKit_FaceProvider_SetRequestedMaximumFaceCount(int32_t) {}
    void UnityARKit_FaceProvider_Shutdown() {}
    void UnityARKit_FaceProvider_Start() {}
    void UnityARKit_FaceProvider_Stop() {}
    int32_t UnityARKit_FaceProvider_TryAcquireFaceBlendCoefficients(TrackableId_t49EAE8AA4B9584E314518723DC22B66496D47AD7, intptr_t*, int32_t*) { return 2; /* Error */ }
    XRResultStatus_tCC9883C2EC8AE64CE75A3B0BD56DEFB134CEC941 UnityARKit_FaceProvider_TryGetBlendShapes(TrackableId_t49EAE8AA4B9584E314518723DC22B66496D47AD7, intptr_t*, int32_t*, int32_t*) { XRResultStatus_tCC9883C2EC8AE64CE75A3B0BD56DEFB134CEC941 s; s.___m_StatusCode = 2; s.___m_NativeStatusCode = 2; return s; }
}
'

MARKER="UnityARKit_FaceProvider_PATCHED_STUBS"

patch_file() {
    local FILE="$1"
    if [ ! -f "$FILE" ]; then
        echo "  [SKIP] Not found: $FILE"
        return
    fi
    if grep -q "$MARKER" "$FILE"; then
        echo "  [INFO] Found existing patch, removing it first..."
        # Delete from the marker line to the end of the file
        sed -i '' "/\/\/ $MARKER/,\$d" "$FILE"
    fi
    # Append the stubs just before the final #pragma clang diagnostic pop
    # We append at end of file which is safe since it's after all declarations
    echo "" >> "$FILE"
    echo "// $MARKER" >> "$FILE"
    echo "$PATCH" >> "$FILE"
    echo "  [OK] Patched: $FILE"
}

BASE="/Users/gavril/Documents/VSCODEPRJ/RedFlag"
FILE_NAME="Il2CppOutputProject/Source/il2cppOutput/Unity.XR.ARKit.FaceTracking.cpp"

echo "=== Patching FaceProvider stubs ==="
patch_file "$BASE/BetterVersion/$FILE_NAME"
patch_file "$BASE/itechARapp/BetterVersion/$FILE_NAME"
echo "=== Done. Now do Shift+Cmd+K then Cmd+R in Xcode ==="
