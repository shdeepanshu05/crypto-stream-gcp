"""Packages crypto_silver so Dataflow workers can import it."""
import setuptools

setuptools.setup(
    name="crypto-silver",
    version="0.1.0",
    packages=setuptools.find_packages(include=["crypto_silver", "crypto_silver.*"]),
)