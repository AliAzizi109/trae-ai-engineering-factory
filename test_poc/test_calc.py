"""Self-contained demo module combining production code and pytest tests.

This module intentionally keeps the ``divide`` function together with its
pytest tests as a compact, single-file demonstration.  In a typical project
layout production code and tests would live in separate directories, but
this structure lets readers see implementation and verification side by
side.

The production function is importable from this module just like any other,
for example::

    from test_poc.test_calc import divide
    result = divide(10.0, 3.0)
"""

import math

import pytest


def divide(a: float, b: float) -> float:
    """Divide two numbers and return the quotient.

    Performs runtime type and value validation on both operands before
    carrying out the division.  Only real numeric values (``int`` or
    ``float``) are accepted; ``bool`` instances, ``complex`` numbers,
    ``NaN``, or non-numeric types are rejected with descriptive errors.

    Args:
        a: The dividend (numerator).
        b: The divisor (denominator). Must not be zero and must not be NaN.

    Returns:
        The result of dividing ``a`` by ``b``.

    Raises:
        TypeError: If ``a`` or ``b`` is not a real numeric value (``int`` or
            ``float``), or if either argument is a ``bool`` or ``complex``.
        ValueError: If ``b`` is zero (division by zero is not allowed), or
            if either argument is ``NaN``.
    """
    # --- Type validation ------------------------------------------------
    allowed_numeric_types = (int, float)
    if isinstance(a, bool) or not isinstance(a, allowed_numeric_types):
        if isinstance(a, bool):
            actual_type = "bool"
        elif isinstance(a, complex):
            actual_type = "complex"
        else:
            actual_type = type(a).__name__
        raise TypeError(
            f"Expected 'a' to be a real number (int or float), "
            f"got {actual_type!r}."
        )
    if isinstance(b, bool) or not isinstance(b, allowed_numeric_types):
        if isinstance(b, bool):
            actual_type = "bool"
        elif isinstance(b, complex):
            actual_type = "complex"
        else:
            actual_type = type(b).__name__
        raise TypeError(
            f"Expected 'b' to be a real number (int or float), "
            f"got {actual_type!r}."
        )

    # --- Value validation -----------------------------------------------
    if math.isnan(a):
        raise ValueError(
            f"Expected 'a' to be a finite number, got NaN."
        )
    if math.isnan(b):
        raise ValueError(
            f"Expected 'b' to be a finite number, got NaN."
        )
    if b == 0:
        raise ValueError("Cannot divide by zero.")

    return a / b


def test_divide() -> None:
    """Pytest test for the divide function covering normal and error paths."""
    # Normal path: valid division
    assert divide(10, 2) == pytest.approx(5.0)
    assert divide(9, 3) == pytest.approx(3.0)
    assert divide(-6, 2) == pytest.approx(-3.0)

    # Zero-divisor path: should raise ValueError
    with pytest.raises(ValueError, match=r"^Cannot divide by zero\.$"):
        divide(10, 0)

    with pytest.raises(ValueError, match=r"^Cannot divide by zero\.$"):
        divide(0, 0)


if __name__ == "__main__":
    # Demonstrate a successful division path first
    print("=== Successful division example ===")
    dividend, divisor = 10, 3
    result = divide(dividend, divisor)
    print(f"divide({dividend}, {divisor}) = {result}")
    print(f"Using pytest.approx check: {result} approx {dividend / divisor}")

    print()

    # Demonstrate the error path (division by zero)
    print("=== Error path example (division by zero) ===")
    try:
        print(divide(10, 0))
    except ValueError as exc:
        print(f"Error: {exc}")
