extends RefCounted


static func inspect(player: Node2D, actors: Dictionary, effects: RefCounted, registry: RefCounted) -> Dictionary:
	var frame: int = player.priority_arbitration_snapshot().frame + 1
	var diagnostic := {"frame": frame, "actors": {}, "effects": {}, "can_commit": false}
	var batches: Array[Dictionary] = []
	var records: Array[Dictionary] = []
	var sources: Array = actors.keys()
	sources.sort()
	for source: String in sources:
		var actor: Node2D = actors[source]
		var before: Dictionary = actor.launch_transaction_snapshot()
		var aim := actor.global_position.direction_to(player.global_position)
		if aim.is_zero_approx():
			aim = Vector2.RIGHT
		var result: Dictionary = actor.prepare_launch_frame(frame, {"runtime_frame": frame, "source_position": _point(actor.global_position), "target_position": _point(player.global_position), "facing_direction": _point(aim), "target_id": "player:1"})
		diagnostic.actors[source] = {"ok": result.get("ok", false), "code": result.get("code", ""), "field": result.get("field", ""), "context": result.get("context", {}), "can_commit": result.ok and actor.can_commit_launch_frame(result.ticket)}
		if result.ok:
			var registered: Array = []
			for fact: Dictionary in result.batch.threat_facts:
				registered.append(fact.attack_generation)
			var published: Array = []
			for fact: Dictionary in registry.snapshot():
				if str(fact.hostile_source_id) == source:
					published.append(fact.attack_generation)
			diagnostic.actors[source]["batch"] = {"phase": result.batch.phase, "registered_generations": registered.slice(0, 64), "retired_generations": result.batch.retired_generations.slice(0, 64), "published_generations": published.slice(0, 64), "extensions": result.batch.threat_extensions.size(), "effects": result.batch.effect_requests.size(), "status_ticks": result.batch.status_tick_requests.size()}
			batches.append({"hostile_source_id": source, "batch": result.batch})
			records.append({"actor": actor, "before": before, "ticket": result.ticket})
	if batches.size() == actors.size():
		var result: Dictionary = effects.prepare_effects(batches, {"run_id": str(player.current_run_id()), "runtime_frame": frame, "actors": actors, "targets": {"player:1": player}, "threat_registry": registry})
		diagnostic.effects = {"ok": result.get("ok", false), "code": result.get("code", ""), "field": result.get("field", ""), "context": result.get("context", {})}
		if result.ok:
			diagnostic.can_commit = effects.can_commit(result.ticket)
			diagnostic.effects["rollback"] = effects.rollback(result.ticket)
	for record: Dictionary in records:
		diagnostic.actors[str(record.actor.hostile_source_id)]["rollback"] = record.actor.rollback_launch_frame(record.ticket) and record.actor.restore_launch_transaction_snapshot(record.before)
	return diagnostic


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
