codeunit 50103 "JB Line Builder"
{
    procedure InsertLineWithDoc(LineObj: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; DocNo: Code[20]) ok: Boolean
    begin
        ok := TryInsertLineWithDoc(LineObj, TemplateName, BatchName, DocNo);
        if not ok then; // keep GetLastErrorText() for caller
    end;

    [TryFunction]
    local procedure TryInsertLineWithDoc(LineObj: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; DocNo: Code[20])
    var
        GenJnlLine: Record "Gen. Journal Line";
        Tok: JsonToken;
        D: Date;
        Amt: Decimal;
        AccTypeTxt: Text;
        BalAccTypeTxt: Text;
        AccType: Enum "Gen. Journal Account Type";
        BalAccType: Enum "Gen. Journal Account Type";
        DocTypeTxt: Text;
        DocType: Enum "Gen. Journal Document Type";
        LineNo: Integer;
        ValTxt: Text;
        ContractTxt: Text;
        ActPeriodTxt: Text;
        BatchHelpers: Codeunit "JB Batch Helpers";
        DimHelpers: Codeunit "JB Dimension Helpers";
    begin
        GenJnlLine.Init();
        GenJnlLine.Validate("Journal Template Name", TemplateName);
        GenJnlLine.Validate("Journal Batch Name", BatchName);

        LineNo := BatchHelpers.GetNextLineNo(TemplateName, BatchName);
        GenJnlLine.Validate("Line No.", LineNo);

        // same Document No. for this set
        GenJnlLine.Validate("Document No.", DocNo);

        // documentType -> enum
        if LineObj.Get('documentType', Tok) and Tok.IsValue() then begin
            DocTypeTxt := UpperCase(Tok.AsValue().AsText());
            DocType := MapDocumentType(DocTypeTxt);
            GenJnlLine.Validate("Document Type", DocType);
        end;

        // documentDate
        if LineObj.Get('documentDate', Tok) and Tok.IsValue() then begin
            if not Evaluate(D, Tok.AsValue().AsText()) then
                Error('Invalid documentDate: %1', Tok.AsValue().AsText());
            GenJnlLine.Validate("Document Date", D);
        end;

        // postingDate
        if LineObj.Get('postingDate', Tok) and Tok.IsValue() then begin
            if not Evaluate(D, Tok.AsValue().AsText()) then
                Error('Invalid postingDate: %1', Tok.AsValue().AsText());
            GenJnlLine.Validate("Posting Date", D);
        end;

        // accountType
        if LineObj.Get('accountType', Tok) and Tok.IsValue() then begin
            AccTypeTxt := UpperCase(Tok.AsValue().AsText());
            AccType := MapAccountType(AccTypeTxt);
            GenJnlLine.Validate("Account Type", AccType);
        end;

        // accountNo
        if LineObj.Get('accountNo', Tok) and Tok.IsValue() then
            GenJnlLine.Validate("Account No.", Tok.AsValue().AsText());

        // balanceAccountType / balAccountType
        if LineObj.Get('balanceAccountType', Tok) and Tok.IsValue() then begin
            BalAccTypeTxt := UpperCase(Tok.AsValue().AsText());
            BalAccType := MapAccountType(BalAccTypeTxt);
            GenJnlLine.Validate("Bal. Account Type", BalAccType);
        end else
            if LineObj.Get('balAccountType', Tok) and Tok.IsValue() then begin
                BalAccTypeTxt := UpperCase(Tok.AsValue().AsText());
                BalAccType := MapAccountType(BalAccTypeTxt);
                GenJnlLine.Validate("Bal. Account Type", BalAccType);
            end;

        // balanceAccountNumber / balAccountNo
        if LineObj.Get('balanceAccountNumber', Tok) and Tok.IsValue() then
            GenJnlLine.Validate("Bal. Account No.", Tok.AsValue().AsText())
        else
            if LineObj.Get('balAccountNo', Tok) and Tok.IsValue() then
                GenJnlLine.Validate("Bal. Account No.", Tok.AsValue().AsText());

        // currencyCode
        if LineObj.Get('currencyCode', Tok) and Tok.IsValue() then
            GenJnlLine.Validate("Currency Code", Tok.AsValue().AsText());

        // amount
        if LineObj.Get('amount', Tok) and Tok.IsValue() then begin
            Amt := Tok.AsValue().AsDecimal();
            GenJnlLine.Validate(Amount, Amt);
        end;

        // description
        if LineObj.Get('description', Tok) and Tok.IsValue() then
            GenJnlLine.Validate(Description, Tok.AsValue().AsText());

        // externalDocumentNumber / externalDocumentNo
        if LineObj.Get('externalDocumentNumber', Tok) and Tok.IsValue() then
            GenJnlLine.Validate("External Document No.", Tok.AsValue().AsText())
        else
            if LineObj.Get('externalDocumentNo', Tok) and Tok.IsValue() then
                GenJnlLine.Validate("External Document No.", Tok.AsValue().AsText());

        // dimensions: contractCode & activityPeriod
        ContractTxt := '';
        ActPeriodTxt := '';
        if LineObj.Get('contractCode', Tok) and Tok.IsValue() then
            ContractTxt := Tok.AsValue().AsText();
        if LineObj.Get('activityPeriod', Tok) and Tok.IsValue() then
            ActPeriodTxt := Tok.AsValue().AsText();

        if (ContractTxt <> '') or (ActPeriodTxt <> '') then
            DimHelpers.ApplyContractAndActPeriodDims(GenJnlLine, ContractTxt, ActPeriodTxt);

        // finally insert
        GenJnlLine.Insert(true);
    end;

    // ---- mappings ----
    local procedure MapAccountType(T: Text): Enum "Gen. Journal Account Type"
    var
        A: Enum "Gen. Journal Account Type";
    begin
        case T of
            'G_L_ACCOUNT', 'G/L ACCOUNT', 'GL', 'G/L', 'G-L', 'G L', 'G_L':
                exit(A::"G/L Account");
            'CUSTOMER', 'CUST':
                exit(A::Customer);
            'VENDOR', 'SUPPLIER', 'VEND':
                exit(A::Vendor);
            'BANK_ACCOUNT', 'BANK ACCOUNT', 'BANK':
                exit(A::"Bank Account");
            'FIXED_ASSET', 'FIXED ASSET', 'FA':
                exit(A::"Fixed Asset");
            'IC_PARTNER', 'INTERCOMPANY', 'IC':
                exit(A::"IC Partner");
            'EMPLOYEE':
                exit(A::Employee);
        end;
        exit(A::"G/L Account");
    end;

    local procedure MapDocumentType(T: Text): Enum "Gen. Journal Document Type"
    var
        E: Enum "Gen. Journal Document Type";
    begin
        case T of
            'PAYMENT':
                exit(E::Payment);
            'INVOICE':
                exit(E::Invoice);
            'CREDIT MEMO', 'CREDIT_MEMO', 'CREDIT':
                exit(E::"Credit Memo");
            'FINANCE CHARGE MEMO', 'FINANCE_CHARGE_MEMO':
                exit(E::"Finance Charge Memo");
            'REMINDER':
                exit(E::Reminder);
            'REFUND':
                exit(E::Refund);
        end;
        exit(E::" ");
    end;
}