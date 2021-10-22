1. Reference tables should be in schema "hafah".
2. Testing tables should be in schema "hafah_python".
3. Functions are safeing in schema "public".
4. Owner of functions is set as "dev".

Before running the functions, you should check the correctness of the above points and possibly make corrections in the bodies functions.

HOW FUNCTIONS WORK:
EXAMPLE OF USAGE:
select * from join_test_account_operations()


As a result you get a rows, where function find a incorrectness. Rows are marked accordingly:
-   +1   - if testing table have an addictional row.
-   -1   - if testing table have a missing row.
-    2   - if testing table have a row, where is incorrect data for the corresponding row in the reference table.

