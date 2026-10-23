CREATE OR REPLACE PROCEDURE BI_WEEKLY_PERFORMANCE_CORPORATE(
    p_date IN DATE
) AS
BEGIN

    EXECUTE IMMEDIATE 'TRUNCATE TABLE periods$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE portfolio$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE disbursement_volume_sme$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE sales_volume_new_customers$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE sales_volume_repeat_customers$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE sales_count_sme$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE sales_count_new_customers$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE sales_count_repeat_customers$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE npl_overdue_debt$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE overdraft$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE overdraft_active$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE overdraft_portfolio$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE portfolio_rdk$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE sales_volume_rdk$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE credit_lines_portfolio$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE total_credit_portfolio$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE credit_lines_sales_volume$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE total_credit_sales_volume$';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE offloading_ratio$';

    ---------------------------------------------------
    -- periods
    ---------------------------------------------------
    INSERT INTO periods$ (date_col)
    SELECT LAST_DAY(p_date) FROM dual;

    ---------------------------------------------------
    -- portfolio
    ---------------------------------------------------
INSERT INTO portfolio$
SELECT p.date_col,
       SUM(NVL(a.dbt_pdue_loc, 0) + NVL(a.balance_loc, 0))
FROM periods$ p
JOIN rs.credit_database_accumulate_new a
  ON a.cred_base_date = p.date_col
WHERE (
    -- ŞƏRT 1: Ümumi korporativ portfel (filtrlərlə birlikdə)
    (
        a.type_dog IN ('CORPORATE')
        AND (LOWER(a.udc_status_value) != 'problem' OR a.udc_status_value IS NULL)
        AND (LOWER(a.rstx) NOT LIKE '%puna%' OR a.rstx IS NULL)
        AND a.by_mb IS NULL
        AND (LOWER(a.var_dog) NOT LIKE '%puna%' OR a.var_dog IS NULL)
    )
    OR
    -- ŞƏRT 2: Bu 4 VÖEN (digər şərtlərdən asılı olmayaraq mütləq daxil edilsin)
    a.tax_number IN ('2006441081', '0ZS6WEV', '2007739931', '1500067521')
)
GROUP BY p.date_col;

    ---------------------------------------------------
    -- Disbursement_Volume_CORP
    ---------------------------------------------------
    INSERT INTO disbursement_volume_sme$
    SELECT p.date_col,
           SUM(c.amount_loc) as disbursement_volume_sme
    FROM periods$ p
    JOIN cbdd_admin.credit_sales_dashboard c
      ON c.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    WHERE c.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- sales_volume_new_customers
    ---------------------------------------------------
    INSERT INTO sales_volume_new_customers$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) as sales_volume_new_customers
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    JOIN rs.agre_id_code_cr aac
      ON am.branch = aac.branch AND am.agr_no = aac.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    WHERE am.type_dog IN ('CORPORATE')
      AND aac.cust_hist_value = 'Новый'
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- sales_volume_repeat_customers
    ---------------------------------------------------
    INSERT INTO sales_volume_repeat_customers$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) as sales_volume_repeat_customers
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    JOIN rs.agre_id_code_cr aac
      ON am.branch = aac.branch AND am.agr_no = aac.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    WHERE am.type_dog IN ('CORPORATE')
      AND (TRIM(UPPER(aac.cust_hist_value)) LIKE '%ПОВТОР%')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- Sales_Count_CORP
    ---------------------------------------------------
    INSERT INTO sales_count_sme$
    SELECT p.date_col,
           COUNT(DISTINCT am.agr_no) as sales_count_sme
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    WHERE am.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;


    -- Sales_Count_new_customers
    ---------------------------------------------------
    INSERT INTO sales_count_new_customers$
    SELECT p.date_col,
           COUNT(DISTINCT am.agr_no) sales_count_new_customers
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_id_code_cr aac
      ON am.branch = aac.branch AND am.agr_no = aac.agr_no
    WHERE am.type_dog IN ('CORPORATE')
      AND (UPPER(aac.cust_hist_value) LIKE '%НОВЫЙ%'
           OR UPPER(aac.cust_hist_value) IN ('YENI','NEW','NOVIY'))
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- Sales_Count_repeat_customers
    ---------------------------------------------------
    INSERT INTO sales_count_repeat_customers$
    SELECT p.date_col,
           COUNT(DISTINCT am.agr_no) sales_count_repeat_customers
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_id_code_cr aac
      ON am.branch = aac.branch AND am.agr_no = aac.agr_no
    WHERE am.type_dog IN ('CORPORATE')
      AND (UPPER(aac.cust_hist_value) LIKE '%ПОВТОР%'
           OR UPPER(aac.cust_hist_value) IN ('TEKRAR','REPEAT','OLD'))
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- NPL_overdue_debt
    ---------------------------------------------------
    INSERT INTO npl_overdue_debt$
    SELECT p.date_col,
           SUM(NVL(a.dbt_pdue_loc,0) + NVL(a.balance_loc,0)) npl_overdue_debt
    FROM periods$ p
    JOIN rs.credit_database_accumulate_new a
      ON a.cred_base_date = p.date_col
    JOIN credit_sales_dashboardd v
      ON v.agr_no = a.agr_no
    WHERE v.rstx = 'Puna Corporat Prekreditovka'
      AND v.subtype_dog = 'PUNA_DEMLAK'
      AND v.udc_status = 'PROBLEM'
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- overdraft
    ---------------------------------------------------
    INSERT INTO overdraft$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) overdraft
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    LEFT JOIN rs.agre_settings_cr cda
      ON cda.branch = am.branch AND cda.agr_no = am.agr_no
    WHERE am.type_dog IN ('CORPORATE')
    AND am.subtype_dog IN ('LOYALLIQ', 'POS', 'SALARYOVERDRAFT')
      AND ((cda.IB_OVERDRAFT_CR IS NOT NULL AND cda.IB_OVERDRAFT_CR <> 'Digər')
           OR UPPER(am.subtype_dog) LIKE '%OVER%')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- overdraft_active
    ---------------------------------------------------
    INSERT INTO overdraft_active$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) overdraft_active
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    JOIN rs.agre_id_code_cr aac
      ON am.branch = aac.branch AND am.agr_no = aac.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    LEFT JOIN rs.agre_settings_cr cda
      ON am.branch = cda.branch AND am.agr_no = cda.agr_no
    WHERE am.type_dog IN ('CORPORATE')
    AND am.subtype_dog IN ('LOYALLIQ', 'POS', 'SALARYOVERDRAFT')
      AND ((cda.IB_OVERDRAFT_CR IS NOT NULL AND cda.IB_OVERDRAFT_CR <> 'Digər')
           OR UPPER(am.subtype_dog) LIKE '%OVER%')
      AND aac.cust_hist_value LIKE '%Повтор%'
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- overdraft_portfolio
    ---------------------------------------------------
    INSERT INTO overdraft_portfolio$
    SELECT p.date_col,
           SUM(NVL(acc.balance_loc,0) + NVL(acc.dbt_pdue_loc,0)) overdraft_portfolio
    FROM periods$ p
    JOIN rs.credit_database_accumulate_new acc
      ON acc.cred_base_date = p.date_col
    JOIN rs.agre_master_credits am
      ON acc.branch = am.branch AND acc.agr_no = am.agr_no
    LEFT JOIN rs.agre_settings_cr cda
      ON am.branch = cda.branch AND am.agr_no = cda.agr_no
    WHERE am.type_dog IN ('CORPORATE')
      AND ((cda.IB_OVERDRAFT_CR IS NOT NULL AND cda.IB_OVERDRAFT_CR <> 'Digər')
           OR UPPER(am.subtype_dog) LIKE '%OVER%')
      AND (NVL(acc.balance_loc,0) + NVL(acc.dbt_pdue_loc,0)) > 0
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- portfolio_rdk
    ---------------------------------------------------
    INSERT INTO portfolio_rdk$
    SELECT p.date_col,
           SUM(NVL(balance_loc,0) + NVL(dbt_pdue_loc,0)) portfolio_rdk
    FROM periods$ p
    JOIN rs.credit_database_accumulate_new a
      ON a.cred_base_date = p.date_col
    WHERE a.var_dog = 'RDK'
      AND a.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- sales_volume_RDK
    ---------------------------------------------------
    INSERT INTO sales_volume_rdk$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) sales_volume_rdk
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    WHERE am.subtype_dog = 'RDK'
      AND am.type_dog IN ('CORPORATE')
      AND am.agr_closed IS NULL
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- credit_lines_portfolio
    ---------------------------------------------------
    INSERT INTO credit_lines_portfolio$
    SELECT p.date_col,
           SUM(NVL(balance_loc,0) + NVL(dbt_pdue_loc,0)) credit_lines_portfolio
    FROM periods$ p
    JOIN rs.credit_database_accumulate_new a
      ON a.cred_base_date = p.date_col
    WHERE a.type_dog IN ('CORPORATE')
      AND a.cred_line = 'Y'
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- total_credit_portfolio
    ---------------------------------------------------
    INSERT INTO total_credit_portfolio$
    SELECT p.date_col,
           SUM(NVL(balance_loc,0) + NVL(dbt_pdue_loc,0)) total_credit_portfolio
    FROM periods$ p
    JOIN rs.credit_database_accumulate_new a
      ON a.cred_base_date = p.date_col
    WHERE a.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- credit_lines_sales_volume
    ---------------------------------------------------
    INSERT INTO credit_lines_sales_volume$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) credit_lines_sales_volume
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_settings_cr cda
      ON am.branch = cda.branch AND am.agr_no = cda.agr_no
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    WHERE cda.cred_line = 'Y'
      AND am.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- total_credit_sales_volume
    ---------------------------------------------------
    INSERT INTO total_credit_sales_volume$
    SELECT p.date_col,
           SUM(aa.amount * NVL(cur.course,1)) total_credit_sales_volume
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    WHERE am.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- offloading_ratio
    ---------------------------------------------------
    INSERT INTO offloading_ratio$
    SELECT p.date_col,
           ROUND(
             SUM(CASE WHEN UPPER(am.subtype_dog) LIKE '%OVER%'
                      THEN aa.amount * NVL(cur.course,1)
                      ELSE 0 END)
             / NULLIF(SUM(aa.amount * NVL(cur.course,1)),0) * 100,2) offloading_ratio
    FROM periods$ p
    JOIN rs.agre_master_credits am
      ON am.agr_signed BETWEEN TRUNC(p.date_col,'MM') AND p.date_col
    JOIN rs.agre_amounts_credits aa
      ON am.branch = aa.branch AND am.agr_no = aa.agr_no
    LEFT JOIN rs.cur_courses cur
      ON am.cur_no = cur.cur_no AND am.agr_signed = cur.course_date
    WHERE am.type_dog IN ('CORPORATE')
    GROUP BY p.date_col;

    ---------------------------------------------------
    -- FINAL RESULT INSERT
    ---------------------------------------------------
     INSERT INTO  CORPORATE_CREDIT_PORTFOLIO(
        дата,
        портфель,
        "Объём_выдач_CORP",
        "объём_продаж_новым_клиентам",
        "Объём_продаж_повторным_клиентам",
        "Количество_продаж_CORP",
        "Количество_продаж_новым_клиентам",
        "Количество_продаж_повторным_клиентам",
        "NPL_просроченная_задолженность",
        "овердрафт",
        "овердрафт_действующим",
        "портфель_овердрафта",
        "портфель_rdk",
        "ОБъём_продаж_RDK",
        "Портфель_кредитных_линий",
        "Общий_кредитный_портфель",
        "Объём_продаж_кредитных_линий",
        "Общий_объем_кредитных_продаж",
        "offloading_ratio"
    )
    SELECT
        p.date_col,
        pr.portfolio,
        vd.disbursement_volume_sme,
        nk.sales_volume_new_customers,
        rk.sales_volume_repeat_customers,
        ks.sales_count_sme,
        kn.sales_count_new_customers,
        kr.sales_count_repeat_customers,
        npl.npl_overdue_debt,
        ov.overdraft,
        od.overdraft_active,
        po.overdraft_portfolio,
        rdp.portfolio_rdk,
        rdv.sales_volume_rdk,
        klp.credit_lines_portfolio,
        okp.total_credit_portfolio,
        klv.credit_lines_sales_volume,
        okv.total_credit_sales_volume,
        off.offloading_ratio
    FROM periods$ p
    LEFT JOIN portfolio$ pr ON pr.date_col = p.date_col
    LEFT JOIN disbursement_volume_sme$ vd ON vd.date_col = p.date_col
    LEFT JOIN sales_volume_new_customers$ nk ON nk.date_col = p.date_col
    LEFT JOIN sales_volume_repeat_customers$ rk ON rk.date_col = p.date_col
    LEFT JOIN sales_count_sme$ ks ON ks.date_col = p.date_col
    LEFT JOIN sales_count_new_customers$ kn ON kn.date_col = p.date_col
    LEFT JOIN sales_count_repeat_customers$ kr ON kr.date_col = p.date_col
    LEFT JOIN npl_overdue_debt$ npl ON npl.date_col = p.date_col
    LEFT JOIN overdraft$ ov ON ov.date_col = p.date_col
    LEFT JOIN overdraft_active$ od ON od.date_col = p.date_col
    LEFT JOIN overdraft_portfolio$ po ON po.date_col = p.date_col
    LEFT JOIN portfolio_rdk$ rdp ON rdp.date_col = p.date_col
    LEFT JOIN sales_volume_rdk$ rdv ON rdv.date_col = p.date_col
    LEFT JOIN credit_lines_portfolio$ klp ON klp.date_col = p.date_col
    LEFT JOIN total_credit_portfolio$ okp ON okp.date_col = p.date_col
    LEFT JOIN credit_lines_sales_volume$ klv ON klv.date_col = p.date_col
    LEFT JOIN total_credit_sales_volume$ okv ON okv.date_col = p.date_col
    LEFT JOIN offloading_ratio$ off ON off.date_col = p.date_col;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20001, 'Xəta: ' || SQLERRM);
END;
