using UnityEngine;

/// <summary>
/// This is a component that modifies the volumetric fog density within a spherical area.
/// </summary>
public class VolumetricFogVolumeModifier : MonoBehaviour
{
	#region Private Attributes

	private static readonly Color DebugColor = Color.chartreuse;
	private static VolumetricFogVolumeModifier instance;

	[Min(0.0f)]
	[SerializeField]
	private float radius = 2.5f;
	[Min(0.0f)]
	[SerializeField]
	private float fallOff = 0.05f;
	[Min(0.0f)]
	[SerializeField]
	private float densityMultiplier = 10.0f;

	#endregion

	#region Properties

	public float Radius
	{
		get { return radius; }
		set { radius = Mathf.Max(value, 0.0f); }
	}

	public float FallOff
	{
		get { return fallOff; }
		set { fallOff = Mathf.Max(value, 0.0f); }
	}

	public float DensityMultiplier
	{
		get { return densityMultiplier; }
		set { densityMultiplier = Mathf.Max(value, 0.0f); }
	}

	public static VolumetricFogVolumeModifier Instance { get { return instance; } }

	#endregion

	#region MonoBehaviour Methods

	private void Awake()
	{
		if (enabled)
		{
			Debug.Assert(instance == null, "There is more than one volume modifier, which is currently unsupported!");
			instance = this;
		}
	}

	private void OnDestroy()
	{
		instance = null;
	}

	private void OnDrawGizmos()
	{
		Gizmos.color = DebugColor;
		Gizmos.DrawWireSphere(transform.position, radius);
	}

	#endregion
}