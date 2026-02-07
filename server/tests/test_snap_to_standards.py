"""Tests for Stage 6: Snap to Standards."""

import pytest

from pipeline.stages.snap_to_standards import SnapToStandards, SnapResult
from pipeline.stages.object_detection import DetectedObject
from pipeline.stages.scale_calibration import STANDARD_CABINET_WIDTHS


@pytest.fixture
def snapper():
    return SnapToStandards()


def make_object(label: str, width_inches: float) -> DetectedObject:
    """Create a mock DetectedObject."""
    return DetectedObject(
        label=label,
        instance_id=0,
        bbox=(0, 0, 100, 100),
        mask=None,
        width_inches=width_inches,
        height_inches=30.0,
        depth_inches=24.0,
        confidence=0.9,
        frame_index=0,
    )


class TestSnapToStandards:
    def test_empty_objects(self, snapper):
        result = snapper.snap([])
        assert result.total_snapped == 0
        assert result.flagged_count == 0

    def test_exact_standard_size_no_flag(self, snapper):
        obj = make_object("base cabinet", 24.0)
        result = snapper.snap([obj])
        assert result.total_snapped == 1
        assert result.flagged_count == 0
        assert result.snapped_objects[0].snapped_width_inches == 24.0
        assert result.snapped_objects[0].deviation_inches == 0.0

    def test_close_to_standard_snaps(self, snapper):
        obj = make_object("base cabinet", 23.5)  # Close to 24"
        result = snapper.snap([obj])
        assert result.snapped_objects[0].snapped_width_inches == 24.0
        assert abs(result.snapped_objects[0].deviation_inches) < 1.0

    def test_far_deviation_flagged(self, snapper):
        obj = make_object("base cabinet", 20.0)  # Closest is 21", deviation = -1
        # Actually 20" is closest to 21", deviation = -1, not flagged
        # Let's use 17" which is between 15 and 18, closest 18, dev = -1, not flagged
        # Use 14" which is between 12 and 15, closest 15, dev = -1, not flagged
        # Need >2" deviation: 10" closest to 9, dev = 1, not flagged
        # Use 7.0: closest to 9, dev = -2, borderline
        # Use 6.0: closest to 9, dev = -3, flagged!
        obj = make_object("base cabinet", 6.0)
        result = snapper.snap([obj])
        assert result.flagged_count == 1
        assert result.snapped_objects[0].is_flagged

    def test_appliance_not_snapped(self, snapper):
        obj = make_object("refrigerator", 35.5)  # Not a cabinet
        result = snapper.snap([obj])
        assert result.snapped_objects[0].snapped_width_inches == 35.5  # Kept raw
        assert not result.snapped_objects[0].is_flagged

    def test_all_standard_sizes_snap_exactly(self, snapper):
        for size in STANDARD_CABINET_WIDTHS:
            obj = make_object("base cabinet", float(size))
            result = snapper.snap([obj])
            assert result.snapped_objects[0].snapped_width_inches == size
            assert result.snapped_objects[0].deviation_inches == 0.0
            assert not result.snapped_objects[0].is_flagged

    def test_mixed_objects(self, snapper):
        objects = [
            make_object("base cabinet", 24.0),
            make_object("upper cabinet", 30.5),
            make_object("refrigerator", 36.0),
            make_object("base cabinet", 5.0),  # Will be flagged
        ]
        result = snapper.snap(objects)
        assert result.total_snapped == 4
        assert result.flagged_count == 1  # Only the 5" base cabinet

    def test_zero_width(self, snapper):
        obj = make_object("base cabinet", 0.0)
        result = snapper.snap([obj])
        assert result.snapped_objects[0].snapped_width_inches == 0.0

    def test_snap_width_nearest(self, snapper):
        # 25" should snap to 24" (closer than 27")
        width, dev = snapper._snap_width(25.0)
        assert width == 24.0
        assert dev == pytest.approx(1.0)

        # 26" should snap to 27" (closer than 24")
        width, dev = snapper._snap_width(26.0)
        assert width == 27.0
        assert dev == pytest.approx(-1.0)

    def test_upper_cabinet_snapped(self, snapper):
        obj = make_object("upper cabinet", 29.0)  # Should snap to 30"
        result = snapper.snap([obj])
        assert result.snapped_objects[0].snapped_width_inches == 30.0

    def test_tall_cabinet_snapped(self, snapper):
        obj = make_object("tall cabinet", 23.0)  # Should snap to 24"
        result = snapper.snap([obj])
        assert result.snapped_objects[0].snapped_width_inches == 24.0
