class_name ReplaySafeValue
extends RefCounted

const MAX_DEPTH := 8


static func is_supported(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_VECTOR2:
			var vector2_value := value as Vector2
			return is_finite(vector2_value.x) and is_finite(vector2_value.y)
		TYPE_VECTOR2I:
			return true
		TYPE_VECTOR3:
			var vector3_value := value as Vector3
			return (
				is_finite(vector3_value.x)
				and is_finite(vector3_value.y)
				and is_finite(vector3_value.z)
			)
		TYPE_VECTOR3I:
			return true
		TYPE_VECTOR4:
			var vector4_value := value as Vector4
			return (
				is_finite(vector4_value.x)
				and is_finite(vector4_value.y)
				and is_finite(vector4_value.z)
				and is_finite(vector4_value.w)
			)
		TYPE_VECTOR4I:
			return true
		TYPE_COLOR:
			var color_value := value as Color
			return (
				is_finite(color_value.r)
				and is_finite(color_value.g)
				and is_finite(color_value.b)
				and is_finite(color_value.a)
			)
		TYPE_ARRAY:
			for child_value: Variant in value as Array:
				if not is_supported(child_value, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key_value: Variant in (value as Dictionary).keys():
				if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
					return false
				if not is_supported((value as Dictionary)[key_value], depth + 1):
					return false
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return true
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			for number_value: Variant in value:
				if not is_finite(float(number_value)):
					return false
			return true
		TYPE_PACKED_VECTOR2_ARRAY:
			for vector_value: Vector2 in value:
				if not is_finite(vector_value.x) or not is_finite(vector_value.y):
					return false
			return true
		TYPE_PACKED_VECTOR3_ARRAY:
			for vector_value: Vector3 in value:
				if (
					not is_finite(vector_value.x)
					or not is_finite(vector_value.y)
					or not is_finite(vector_value.z)
				):
					return false
			return true
		TYPE_PACKED_COLOR_ARRAY:
			for color_value: Color in value:
				if (
					not is_finite(color_value.r)
					or not is_finite(color_value.g)
					or not is_finite(color_value.b)
					or not is_finite(color_value.a)
				):
					return false
			return true
		_:
			return false
