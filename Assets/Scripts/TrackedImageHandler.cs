using UnityEngine;
using UnityEngine.XR.ARFoundation;

public class TrackedImageHandler : MonoBehaviour
{
    private ARTrackedImageManager m_TrackedImageManager;

    void Awake()
    {
        m_TrackedImageManager = GetComponent<ARTrackedImageManager>();
    }

    void OnEnable()
    {
        m_TrackedImageManager.trackedImagesChanged += OnTrackedImagesChanged;
    }

    void OnDisable()
    {
        m_TrackedImageManager.trackedImagesChanged -= OnTrackedImagesChanged;
    }

    void OnTrackedImagesChanged(ARTrackedImagesChangedEventArgs eventArgs)
    {
        foreach (var trackedImage in eventArgs.added) {
            UpdateImage(trackedImage);
        }
        foreach (var trackedImage in eventArgs.updated) {
            if (trackedImage.trackingState == UnityEngine.XR.ARSubsystems.TrackingState.Tracking) {
                UpdateImage(trackedImage);
            }
        }
    }

    void UpdateImage(ARTrackedImage trackedImage)
    {
        // Image name is the ID from the ReferenceImageLibrary
        string posterID = trackedImage.referenceImage.name;
        BridgeManager.Instance.OnPosterDetected(posterID);
    }
}
