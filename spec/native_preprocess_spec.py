import ctypes
import math
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class NativeFilterTests(unittest.TestCase):
    def setUp(self):
        library = ROOT / "native/preprocess/build/moire-host.so"
        self.assertTrue(library.exists(), "the bounded native single-page prototype is not built")
        self.library = ctypes.CDLL(str(library))
        native = self.library.koocomic_filter
        native.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int, ctypes.c_int,
                           ctypes.c_int, ctypes.c_int, ctypes.c_float, ctypes.c_size_t, ctypes.c_size_t]
        native.restype = ctypes.c_int
        self.apply = lambda buffer, *args: native(buffer, *args, len(buffer)) if len(args) == 6 else native(buffer, *args)

    def test_constant_and_zero_strength(self):
        buffer = (ctypes.c_ubyte * (64 * 64))(*([128] * (64 * 64)))
        self.assertEqual(self.apply(buffer, 64, 64, 64, 0, 0.8, 1024 * 1024), 0)
        self.assertLessEqual(max(abs(value - 128) for value in buffer), 1)
        before = bytes(buffer)
        self.assertEqual(self.apply(buffer, 64, 64, 64, 0, 0, 1024 * 1024), 0)
        self.assertEqual(bytes(buffer), before)

    def test_diagonal_high_frequency_is_attenuated(self):
        original = [int(128 + 60 * math.cos(2 * math.pi * 20 * (x + y) / 64))
                    for y in range(64) for x in range(64)]
        buffer = (ctypes.c_ubyte * len(original))(*original)
        self.assertEqual(self.apply(buffer, 64, 64, 64, 0, 1, 1024 * 1024), 0)
        self.assertLess(max(buffer) - min(buffer), (max(original) - min(original)) * 0.3)

    def test_color_and_alpha_are_preserved(self):
        original = [120, 95, 65, 231] * (64 * 64)
        buffer = (ctypes.c_ubyte * len(original))(*original)
        self.assertEqual(self.apply(buffer, 64, 64, 256, 1, 0.8, 1024 * 1024), 0)
        self.assertLessEqual(max(abs(buffer[i] - original[i]) for i in range(len(original))), 2)
        self.assertTrue(all(buffer[i] == 231 for i in range(3, len(buffer), 4)))

    def test_invalid_geometry_and_budget_rejected_without_writing(self):
        buffer = (ctypes.c_ubyte * 4096)(*([17] * 4096))
        before = bytes(buffer)
        for args in [(0, 64, 64, 0, 0.8, 1000000), (63, 64, 64, 0, 0.8, 1000000),
                     (64, 64, 63, 0, 0.8, 1000000), (64, 64, 64, 0, 0.8, 1),
                     (64, 64, 64, 0, float("nan"), 1000000)]:
            self.assertNotEqual(self.apply(buffer, *args), 0)
            self.assertEqual(bytes(buffer), before)

    def test_short_buffer_rejected_without_writing(self):
        buffer = (ctypes.c_ubyte * 4096)(*([17] * 4096))
        before = bytes(buffer)
        self.assertNotEqual(self.apply(buffer, 64, 64, 64, 0, 0.8, 1000000, 4095), 0)
        self.assertEqual(bytes(buffer), before)

    def test_byte_span_cannot_overflow_native_signed_indices(self):
        buffer = (ctypes.c_ubyte * 1)(17)
        # Zero strength avoids dereferencing the advertised geometry in the old wrapper.
        self.assertNotEqual(self.apply(buffer, 32768, 32768, 131072, 1, 0, 2**40, 2**32), 0)
        self.assertEqual(buffer[0], 17)


if __name__ == "__main__":
    unittest.main()
