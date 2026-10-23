CREATE OR REPLACE PROCEDURE BE_WEEKLY_PERFORMANCE_RKO_NON_INTEREST_INCOME(
    p_date IN DATE
) AS
BEGIN

    ---------------------------------------------------
    -- CLEAN TEMP TABLES
    ---------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE periods$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE domestic_payments$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE non_interest_income$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE swift_payments$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE account_service$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE dealing_income$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE cash_ops_total$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE rko_segmented_all$';

    ---------------------------------------------------
    -- PERIODS
    ---------------------------------------------------
    INSERT INTO periods$ (date_col)
    SELECT LAST_DAY(p_date) FROM dual;

    ---------------------------------------------------
    -- 1. DOMESTIC PAYMENTS
    ---------------------------------------------------
    INSERT INTO domestic_payments$
    SELECT
        LAST_DAY(TRUNC(value_date)) AS report_date,
        SUM(NVL(settlement_transh_azn,0)) AS total_domestic_commission
    FROM RKO_OVERVIEW_MAIN_TAXNUMBER
    WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
    GROUP BY LAST_DAY(TRUNC(value_date));

    ---------------------------------------------------
    -- 2. NON INTEREST INCOME
    ---------------------------------------------------
    INSERT INTO non_interest_income$
    SELECT
        LAST_DAY(TRUNC(value_date)) AS report_date,
        SUM(
            NVL(cash_transactions, 0) +
            NVL(dealing, 0) +
            NVL(net_income_or_cur_ops, 0) +
            NVL(settlement_transh_azn, 0) +
            NVL(settlement_transh_val, 0) +
            NVL(other, 0) +
            NVL(pc, 0) +
            NVL(pos, 0)*0.5 +
            NVL(zp, 0)
        ) AS total_commission_income
    FROM RKO_OVERVIEW_MAIN_TAXNUMBER
  --  WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
    GROUP BY LAST_DAY(TRUNC(value_date));

    ---------------------------------------------------
    -- 3. SWIFT PAYMENTS
    ---------------------------------------------------
    INSERT INTO swift_payments$
    SELECT
        LAST_DAY(TRUNC(value_date)) AS report_date,
        SUM(NVL(settlement_transh_val,0)) AS swift_commission_income
    FROM RKO_OVERVIEW_MAIN_TAXNUMBER
    WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
    GROUP BY LAST_DAY(TRUNC(value_date));

    ---------------------------------------------------
    -- 4. ACCOUNT SERVICE
    ---------------------------------------------------
    INSERT INTO account_service$
    SELECT
        LAST_DAY(TRUNC(value_date)) AS report_date,
        SUM(NVL(other,0)) AS account_service_commission_cash
    FROM RKO_OVERVIEW_MAIN_TAXNUMBER
    WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
    GROUP BY LAST_DAY(TRUNC(value_date));

    ---------------------------------------------------
    -- 5. DEALING
    ---------------------------------------------------
    INSERT INTO dealing_income$
    SELECT
        LAST_DAY(TRUNC(value_date)) AS report_date,
        SUM(NVL(dealing,0)) AS fx_dealing_income
    FROM RKO_OVERVIEW_MAIN_TAXNUMBER
    WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
    GROUP BY LAST_DAY(TRUNC(value_date));

    ---------------------------------------------------
    -- 6. CASH OPS
    ---------------------------------------------------
    INSERT INTO cash_ops_total$
    SELECT
        LAST_DAY(TRUNC(value_date)) AS report_date,
        SUM(NVL(cash_transactions,0)) AS cash_operations_total
    FROM RKO_OVERVIEW_MAIN_TAXNUMBER
    WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
    GROUP BY LAST_DAY(TRUNC(value_date));

    ---------------------------------------------------
    -- 7. RKO SEGMENTED (YENI M?NTIQ)
    ---------------------------------------------------
    INSERT INTO rko_segmented_all$
    WITH credit_base_distinct AS (
        SELECT DISTINCT
            tax_number,
            type_dog,
            cred_base_date
        FROM rs.credit_database_accumulate_new
        WHERE cred_base_date = LAST_DAY(p_date)
    ),
    rko_aggregated AS (
        SELECT
            tax_number,
            LAST_DAY(TRUNC(value_date)) AS rko_month,
            SUM(NVL(total_rko,0)) AS total_rko_sum,
            MAX(SEQMENT_KL) AS SEQMENT_KL
        FROM RKO_OVERVIEW_MAIN_TAXNUMBER
        WHERE LAST_DAY(TRUNC(value_date)) = LAST_DAY(p_date)
        GROUP BY tax_number, LAST_DAY(TRUNC(value_date))
    )
    SELECT
        r.rko_month AS report_date,
        -- KREDITI OLANLAR
        SUM(CASE WHEN c.type_dog = 'CORPORATE' THEN r.total_rko_sum ELSE 0 END) AS rko_corp_with_loans,
        SUM(CASE WHEN c.type_dog = 'SME' THEN r.total_rko_sum ELSE 0 END) AS rko_sme_with_loans,
        SUM(CASE WHEN c.type_dog IN ('MICRO','MICRO_SME') THEN r.total_rko_sum ELSE 0 END) AS rko_mikro_with_loans,
        -- KREDITI OLMAYANLAR
        SUM(CASE WHEN c.tax_number IS NULL AND r.SEQMENT_KL IN ('Kiçik','Orta') THEN r.total_rko_sum ELSE 0 END) AS rko_sme_no_loans,
        SUM(CASE WHEN c.tax_number IS NULL AND r.SEQMENT_KL = 'Iri' THEN r.total_rko_sum ELSE 0 END) AS rko_corp_no_loans,
        SUM(CASE WHEN c.tax_number IS NULL AND r.SEQMENT_KL = 'Mikro' THEN r.total_rko_sum ELSE 0 END) AS rko_mikro_no_loans
    FROM rko_aggregated r
    LEFT JOIN credit_base_distinct c
        ON r.tax_number = c.tax_number
        AND r.rko_month = c.cred_base_date
    GROUP BY r.rko_month;

    ---------------------------------------------------
    -- DELETE OLD DATA
    ---------------------------------------------------
    DELETE FROM RKO_NON_INTEREST_INCOME
    WHERE report_date = LAST_DAY(p_date);

    ---------------------------------------------------
    -- FINAL INSERT
    ---------------------------------------------------
    INSERT INTO RKO_NON_INTEREST_INCOME(
        report_date,
        total_domestic_commission,
        total_commission_income,
        swift_commission_income,
        account_service_commission_cash,
        fx_dealing_income,
        cash_operations_total,
        rko_corp_with_loans,
        rko_sme_with_loans,
        rko_mikro_with_loans,
        rko_sme_no_loans,
        rko_corp_no_loans,
        rko_mikro_no_loans
    )
    SELECT
        p.date_col,
        dp.total_domestic_commission,
        nii.total_commission_income,
        sp.swift_commission_income,
        asrv.account_service_commission_cash,
        di.fx_dealing_income,
        cot.cash_operations_total,
        rsa.rko_corp_with_loans,
        rsa.rko_sme_with_loans,
        rsa.rko_mikro_with_loans,
        rsa.rko_sme_no_loans,
        rsa.rko_corp_no_loans,
        rsa.rko_mikro_no_loans
    FROM periods$ p
    LEFT JOIN domestic_payments$ dp ON p.date_col = dp.report_date
    LEFT JOIN non_interest_income$ nii ON p.date_col = nii.report_date
    LEFT JOIN swift_payments$ sp ON p.date_col = sp.report_date
    LEFT JOIN account_service$ asrv ON p.date_col = asrv.report_date
    LEFT JOIN dealing_income$ di ON p.date_col = di.report_date
    LEFT JOIN cash_ops_total$ cot ON p.date_col = cot.report_date
    LEFT JOIN rko_segmented_all$ rsa ON p.date_col = rsa.report_date;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(
            -20001,
            'BE_WEEKLY_PERFORMANCE_RKO_NON_INTEREST_INCOME ERROR: ' || SQLERRM
        );
END;
