package uuid

import "testing"

// Calibration (throwaway) for #188: a server-only diff whose Go suite fails must end with gate red.
func TestCalibrationThrowawayPlantedFailure(t *testing.T) {
	t.Fatal("calibration (throwaway): planted failure — gate must go red on a server-only diff")
}
