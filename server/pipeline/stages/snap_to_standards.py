"""Stage 6: Snap to Standards — Match raw measurements to standard cabinet sizes.

Kitchen cabinets come in standard widths. This stage snaps measured
widths to the nearest standard size and flags deviations >2 inches.
"""

from dataclasses import dataclass

from .object_detection import DetectedObject
from .scale_calibration import STANDARD_CABINET_WIDTHS


@dataclass
class SnappedObject:
    """An object with its measurement snapped to standard size."""
    object: DetectedObject
    raw_width_inches: float
    snapped_width_inches: float
    deviation_inches: float
    is_flagged: bool  # deviation > 2 inches


@dataclass
class SnapResult:
    """Result of snap-to-standards stage."""
    snapped_objects: list[SnappedObject]
    flagged_count: int
    total_snapped: int


class SnapToStandards:
    """Snap cabinet measurements to standard sizes."""

    # Maximum acceptable deviation (inches)
    MAX_DEVIATION = 2.0

    # Object types that should be snapped to standard cabinet widths
    CABINET_TYPES = {"base cabinet", "upper cabinet", "tall cabinet"}

    def snap(self, objects: list[DetectedObject]) -> SnapResult:
        """Snap object widths to nearest standard cabinet size.

        Only applies to cabinet-type objects. Appliances keep raw measurements.

        Args:
            objects: Detected objects with raw measurements

        Returns:
            SnapResult with snapped measurements and flags
        """
        snapped_objects: list[SnappedObject] = []

        for obj in objects:
            if obj.label in self.CABINET_TYPES:
                snapped_width, deviation = self._snap_width(obj.width_inches)
                is_flagged = abs(deviation) > self.MAX_DEVIATION

                # Update the object's standard_width
                obj.standard_width_inches = snapped_width
                obj.deviation_inches = deviation

                snapped_objects.append(SnappedObject(
                    object=obj,
                    raw_width_inches=obj.width_inches,
                    snapped_width_inches=snapped_width,
                    deviation_inches=deviation,
                    is_flagged=is_flagged,
                ))
            else:
                # Appliances: keep raw width, no snapping
                snapped_objects.append(SnappedObject(
                    object=obj,
                    raw_width_inches=obj.width_inches,
                    snapped_width_inches=obj.width_inches,
                    deviation_inches=0,
                    is_flagged=False,
                ))

        flagged = sum(1 for s in snapped_objects if s.is_flagged)

        return SnapResult(
            snapped_objects=snapped_objects,
            flagged_count=flagged,
            total_snapped=len(snapped_objects),
        )

    def _snap_width(self, width_inches: float) -> tuple[float, float]:
        """Snap a width to the nearest standard cabinet size.

        Returns (snapped_width, deviation).
        """
        if width_inches <= 0:
            return 0.0, 0.0

        nearest = min(STANDARD_CABINET_WIDTHS, key=lambda s: abs(s - width_inches))
        deviation = width_inches - nearest
        return float(nearest), deviation
