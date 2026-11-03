## The graphics the game is drawn on (v2.5), for where the land starts on a machine it hasn't measured yet
## (land.gd): integrated graphics, or a software renderer, begin a few effects down. Dad's 14-inch Lenovo
## (Alex, 11-03) likely draws an Iris Xe or a UHD, an eighth to a twentieth of the RTX 3070 the land was
## tuned on (docs/v25/v25-pass.md).
extends RefCounted


static func weak(kind: int, vendor: String, adapter: String) -> bool:
	## kind: RenderingServer.get_video_adapter_type(), which the driver knows on Vulkan and Direct3D 12; on
	## OpenGL it's always OTHER, and the name tells it
	if kind == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or kind == RenderingDevice.DEVICE_TYPE_CPU or kind == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
		return true
	if kind == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return false
	var n: String = (vendor + " " + adapter).to_lower()
	for soft in ["llvmpipe", "swiftshader", "softpipe", "basic render"]:
		if n.contains(soft):
			return true
	if n.contains("intel"):
		return not n.contains("arc") ## (Intel's Arc cards are discrete)
	if n.contains("amd") or n.contains("ati ") or n.contains("radeon"):
		## a Ryzen's graphics are "AMD Radeon(TM) Graphics" or "...Vega 8 Graphics"; the cards are "RX ..."
		return (n.contains("radeon(tm) graphics") or n.contains("radeon graphics") or n.contains("vega")) and not n.contains(" rx ")
	return false


static func weak_here() -> bool:
	return weak(RenderingServer.get_video_adapter_type(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name())
