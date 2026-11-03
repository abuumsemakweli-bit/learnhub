from datetime import datetime, timezone, timedelta
import unittest

from server import _server_time_offset


class ServerTimeTests(unittest.TestCase):
    def test_local_server_timestamp_is_normalized_to_utc(self) -> None:
        local_now = datetime(
            2026, 10, 23, 17, 36, tzinfo=timezone(timedelta(hours=3))
        )
        server_timestamp = int(
            datetime(2026, 10, 23, 17, 36, tzinfo=timezone.utc).timestamp()
        )

        self.assertEqual(
            _server_time_offset(server_timestamp, local_now=local_now), 10_800
        )

    def test_utc_server_timestamp_is_not_shifted(self) -> None:
        local_now = datetime(
            2026, 10, 23, 17, 36, tzinfo=timezone(timedelta(hours=3))
        )
        utc_timestamp = int(
            datetime(2026, 10, 23, 14, 36, tzinfo=timezone.utc).timestamp()
        )

        self.assertEqual(_server_time_offset(utc_timestamp, local_now=local_now), 0)


if __name__ == "__main__":
    unittest.main()
