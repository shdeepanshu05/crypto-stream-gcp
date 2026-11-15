"""Entry point: python main.py coingecko | fx. One image, two Cloud Run jobs."""
import argparse
import logging
import os
import sys

import coingecko
import fx
from common import setup_logging

JOBS = {
    "coingecko": (coingecko.run, "coingecko-markets"),
    "fx": (fx.run, "fx-rates"),
}


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("job", choices=sorted(JOBS))
    args = parser.parse_args()

    project_id = os.environ["GCP_PROJECT_ID"]
    run, default_topic = JOBS[args.job]
    topic_id = os.environ.get("TOPIC", default_topic)

    try:
        run(project_id, topic_id)
    except Exception:
        logging.exception("job failed", extra={"fields": {"job": args.job}})
        sys.exit(1)  # non-zero exit = Cloud Run marks the execution as failed


if __name__ == "__main__":
    main()