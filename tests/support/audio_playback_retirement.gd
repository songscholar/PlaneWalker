extends RefCounted


static func released(references: Array[WeakRef]) -> bool:
	return references.all(func(reference: WeakRef): return reference.get_ref() == null)


static func await_release(tree: SceneTree, references: Array[WeakRef], timeout_usec: int = 1000000) -> bool:
	# Audio mixing follows wall time even when scene timers are fixed-FPS accelerated.
	var deadline := Time.get_ticks_usec() + maxi(0, timeout_usec)
	while not released(references):
		if Time.get_ticks_usec() >= deadline:
			return false
		await tree.process_frame
	return true
