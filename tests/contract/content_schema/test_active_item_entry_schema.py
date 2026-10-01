import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = ROOT / "data/schemas/content_entry_v2.schema.json"

PARAMETER_CONTRACTS = {
    "absolute_zero": {
        "radius": ("number", 32, 512),
        "duration_frames": ("integer", 1, 600),
        "weakpoint_bonus": ("number", 0, 3),
        "energy_cost": ("number", 0, 100),
    },
    "paradox_beacon": {
        "rewind_frames": ("integer", 1, 600),
        "echo_damage_multiplier": ("number", 0, 3),
        "energy_cost": ("number", 0, 100),
    },
    "gravity_snare": {
        "radius": ("number", 32, 512),
        "duration_frames": ("integer", 1, 600),
        "slow_ratio": ("number", 0, 0.9),
        "energy_cost": ("number", 0, 100),
    },
    "redline_injector": {
        "duration_frames": ("integer", 1, 600),
        "speed_multiplier": ("number", 1, 3),
        "health_cost_ratio": ("number", 0, 0.5),
    },
    "blood_price": {
        "duration_frames": ("integer", 1, 600),
        "damage_multiplier": ("number", 1, 5),
        "health_cost_ratio": ("number", 0, 0.5),
    },
    "aegis_reversal": {
        "duration_frames": ("integer", 1, 600),
        "counter_multiplier": ("number", 0, 5),
        "energy_cost": ("number", 0, 100),
    },
    "railshot": {
        "pierce_bonus": ("integer", 1, 20),
        "damage_multiplier": ("number", 1, 5),
        "ammo_refund": ("integer", 0, 20),
    },
    "army_of_yesterday": {
        "echo_count": ("integer", 1, 8),
        "duration_frames": ("integer", 1, 600),
        "echo_damage_multiplier": ("number", 0, 2),
        "energy_cost": ("number", 0, 100),
    },
}


class ActiveItemEntrySchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.validator = Draft202012Validator(cls.schema)

    def test_schema_is_valid_draft_2020_12(self) -> None:
        Draft202012Validator.check_schema(self.schema)

    def test_all_handlers_accept_exact_parameters_and_inclusive_bounds(self) -> None:
        for handler_id, contract in PARAMETER_CONTRACTS.items():
            with self.subTest(handler=handler_id, boundary="nominal"):
                self.assertValid(self.active_entry(handler_id))

            for boundary_index, boundary_name in [(1, "minimum"), (2, "maximum")]:
                parameters = {
                    parameter_id: definition[boundary_index]
                    for parameter_id, definition in contract.items()
                }
                with self.subTest(handler=handler_id, boundary=boundary_name):
                    self.assertValid(self.active_entry(handler_id, parameters))

    def test_every_parameter_rejects_missing_wrong_type_and_out_of_bounds(self) -> None:
        wrong_values = [True, "1", None, [], {}]
        for handler_id, contract in PARAMETER_CONTRACTS.items():
            for parameter_id, (value_type, minimum, maximum) in contract.items():
                missing = self.active_entry(handler_id)
                missing["active_parameters"].pop(parameter_id)
                with self.subTest(
                    handler=handler_id,
                    parameter=parameter_id,
                    mutation="missing",
                ):
                    self.assertInvalid(missing)

                for wrong_value in wrong_values:
                    wrong_type = self.active_entry(handler_id)
                    wrong_type["active_parameters"][parameter_id] = wrong_value
                    with self.subTest(
                        handler=handler_id,
                        parameter=parameter_id,
                        mutation=f"wrong_type_{type(wrong_value).__name__}",
                    ):
                        self.assertInvalid(wrong_type)

                below = self.active_entry(handler_id)
                below["active_parameters"][parameter_id] = minimum - 1
                with self.subTest(
                    handler=handler_id,
                    parameter=parameter_id,
                    mutation="below_minimum",
                ):
                    self.assertInvalid(below)

                above = self.active_entry(handler_id)
                above["active_parameters"][parameter_id] = maximum + 1
                with self.subTest(
                    handler=handler_id,
                    parameter=parameter_id,
                    mutation="above_maximum",
                ):
                    self.assertInvalid(above)

                if value_type == "integer":
                    fractional = self.active_entry(handler_id)
                    fractional["active_parameters"][parameter_id] = minimum + 0.5
                    with self.subTest(
                        handler=handler_id,
                        parameter=parameter_id,
                        mutation="fractional_integer",
                    ):
                        self.assertInvalid(fractional)

    def test_each_handler_rejects_additional_and_cross_handler_parameters(self) -> None:
        handler_ids = list(PARAMETER_CONTRACTS)
        for index, handler_id in enumerate(handler_ids):
            additional = self.active_entry(handler_id)
            additional["active_parameters"]["script_path"] = 1
            with self.subTest(handler=handler_id, mutation="additional"):
                self.assertInvalid(additional)

            other_handler = handler_ids[(index + 1) % len(handler_ids)]
            crossed = self.active_entry(
                handler_id,
                self.valid_parameters(other_handler),
            )
            with self.subTest(
                handler=handler_id,
                mutation=f"parameters_from_{other_handler}",
            ):
                self.assertInvalid(crossed)

    def test_number_parameters_accept_integral_json_numbers(self) -> None:
        for handler_id, contract in PARAMETER_CONTRACTS.items():
            entry = self.active_entry(handler_id)
            for parameter_id, (value_type, minimum, _maximum) in contract.items():
                if value_type == "number":
                    entry["active_parameters"][parameter_id] = int(minimum)
            with self.subTest(handler=handler_id):
                self.assertValid(entry)

    def active_entry(
        self,
        handler_id: str,
        parameters: dict[str, object] | None = None,
    ) -> dict[str, object]:
        return {
            "id": f"test_{handler_id}",
            "category": "item",
            "availability": ["LAUNCH", "EXPANSION"],
            "name_key": "TEST_ACTIVE_ITEM_NAME",
            "description_key": "TEST_ACTIVE_ITEM_DESC",
            "tags": ["active", "risk", "freeze_burst"],
            "compatibility": {"archetype_ids": ["freeze_burst"]},
            "effects": {},
            "kind": "time",
            "archetype": "freeze_burst",
            "role": "risk",
            "rarity": "rare",
            "icon_id": f"content_test_{handler_id}",
            "item_mode": "active",
            "active_handler_id": handler_id,
            "cooldown_frames": 900,
            "active_parameters": copy.deepcopy(
                parameters
                if parameters is not None
                else self.valid_parameters(handler_id)
            ),
        }

    def valid_parameters(self, handler_id: str) -> dict[str, int | float]:
        result: dict[str, int | float] = {}
        for parameter_id, (value_type, minimum, maximum) in (
            PARAMETER_CONTRACTS[handler_id].items()
        ):
            if value_type == "integer":
                result[parameter_id] = int(minimum)
            else:
                result[parameter_id] = (minimum + maximum) / 2
        return result

    def assertValid(self, value: dict[str, object]) -> None:
        errors = list(self.validator.iter_errors(value))
        self.assertEqual(errors, [], self.render_errors(errors))

    def assertInvalid(self, value: dict[str, object]) -> None:
        errors = list(self.validator.iter_errors(value))
        self.assertTrue(errors, "expected the content-entry schema to reject the value")

    @staticmethod
    def render_errors(errors: list) -> str:
        return "\n".join(
            f"{'/'.join(str(part) for part in error.absolute_path)}: {error.message}"
            for error in errors
        )


if __name__ == "__main__":
    unittest.main()
