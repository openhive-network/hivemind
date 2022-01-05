import pytest

import replay_benchmark_parser as parser





def test_remove_unused_key_from_dict(sample_measurement):
    parser.remove_unused_key(sample_measurement, 'index_memory_details_cntr')

    assert sample_measurement == {"block_number": 5000000,
                                  "real_ms": 877896,
                                  "cpu_ms": 560396,
                                  "current_mem": 7183280,
                                  "peak_mem": 7183280,
                                  }


def test_remove_unused_key_from_list_of_dicts(sample_measurement):
    actual = [sample_measurement, sample_measurement.copy()]
    parser.remove_unused_key(actual, 'index_memory_details_cntr')

    assert actual == [{"block_number": 5000000,
                       "real_ms": 877896,
                       "cpu_ms": 560396,
                       "current_mem": 7183280,
                       "peak_mem": 7183280,
                       },
                      {"block_number": 5000000,
                       "real_ms": 877896,
                       "cpu_ms": 560396,
                       "current_mem": 7183280,
                       "peak_mem": 7183280,
                       },
                      ]
