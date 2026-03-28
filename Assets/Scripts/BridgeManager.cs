using UnityEngine;
using TMPro;
using System.Collections;
using System.Collections.Generic;
using UnityEngine.XR.ARFoundation;

public class BridgeManager : MonoBehaviour
{
    public static BridgeManager Instance;

    [Header("UI & References")]
    public GameObject posterObject;      // The Quad prefab or instance
    public GameObject posterLabelObject; // The TMP Text
    public GameObject worldCanvasObject; // The Canvas
    
    private TMP_Text statusLabel;
    private Material posterMaterial;
    private ARTrackedImageManager m_TrackedImageManager;

    [Header("Persistence")]
    private Dictionary<string, Texture2D> posterTextures = new Dictionary<string, Texture2D>();
    private string currentPosterID = "";

    void Awake()
    {
        Instance = this;
    }

    void Start()
    {
        // Try to find the Image Manager automatically
        m_TrackedImageManager = FindFirstObjectByType<ARTrackedImageManager>();
        if (m_TrackedImageManager != null)
        {
            m_TrackedImageManager.trackedImagesChanged += OnTrackedImagesChanged;
            Debug.Log("BridgeManager: Linked to ARTrackedImageManager");
        }

        // Initialize components from generic GameObjects
        if (posterObject != null) posterMaterial = posterObject.GetComponent<MeshRenderer>().material;
        if (posterLabelObject != null) statusLabel = posterLabelObject.GetComponent<TMP_Text>();
        
        if (worldCanvasObject != null)
        {
            worldCanvasObject.GetComponent<Canvas>().transform.localScale = new Vector3(0.001f, 0.001f, 0.001f);
        }
    }

    void OnDestroy()
    {
        if (m_TrackedImageManager != null) m_TrackedImageManager.trackedImagesChanged -= OnTrackedImagesChanged;
    }

    // --- AR DETECTION LOGIC ---
    void OnTrackedImagesChanged(ARTrackedImagesChangedEventArgs eventArgs)
    {
        foreach (var trackedImage in eventArgs.added) {
            OnPosterDetected(trackedImage.referenceImage.name);
        }
        foreach (var trackedImage in eventArgs.updated) {
            if (trackedImage.trackingState == UnityEngine.XR.ARSubsystems.TrackingState.Tracking) {
                OnPosterDetected(trackedImage.referenceImage.name);
            }
        }
    }

    public void OnPosterDetected(string id)
    {
        if (currentPosterID == id) return;
        currentPosterID = id;
        
        if (!posterTextures.ContainsKey(id)) {
            Texture2D newTex = new Texture2D(1024, 1024);
            Color[] clear = new Color[1024 * 1024];
            for(int i=0; i<clear.Length; i++) clear[i] = Color.clear;
            newTex.SetPixels(clear);
            newTex.Apply();
            posterTextures[id] = newTex;
        }

        if (posterMaterial != null) posterMaterial.mainTexture = posterTextures[id];
        if (statusLabel != null) statusLabel.text = "POSTER: " + id;
        
        Debug.Log("BridgeManager: Switched to canvas for " + id);
    }

    // --- XCODE COMMUNICATION ---
    public void OnDrawPoint(string data)
    {
        if (string.IsNullOrEmpty(currentPosterID)) return;

        string[] parts = data.Split(',');
        if (parts.Length < 3) return;

        float x = float.Parse(parts[0]);
        float y = float.Parse(parts[1]);
        Color color = ParseColor(parts[2]);

        DrawOnTexture(posterTextures[currentPosterID], x, y, color);
    }

    private void DrawOnTexture(Texture2D tex, float x, float y, Color color)
    {
        int px = (int)(x * tex.width);
        int py = (int)((1 - y) * tex.height);

        for (int i = -20; i < 20; i++) {
            for (int j = -20; j < 20; j++) {
                int tx = px + i;
                int ty = py + j;
                if (tx >= 0 && tx < tex.width && ty >= 0 && ty < tex.height)
                    tex.SetPixel(tx, ty, color);
            }
        }
        tex.Apply();
    }

    private Color ParseColor(string name) {
        if (name == "LIME") return new Color(0.792f, 0.992f, 0f);
        if (name == "PINK") return new Color(1f, 0.42f, 0.608f);
        if (name == "ULTRA") return new Color(0.675f, 0.537f, 1f);
        return Color.white;
    }
}
