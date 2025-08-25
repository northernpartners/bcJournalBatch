codeunit 50103 "JB Line Builder"
{
    procedure InsertLineWithDoc(LineObj: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; DocNo: Code[20]; DefaultPostingDate: Date) ok: Boolean
    begin
        ok := TryInsertLineWithDoc(LineObj, TemplateName, BatchName, DocNo, DefaultPostingDate);
        if not ok then; // keep GetLastErrorText() for caller
    end;

    [TryFunction]
    local procedure TryInsertLineWithDoc(LineObj: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; DocNo: Code[20]; DefaultPostingDate: Date)
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
        DimHelper: Codeunit "JB Dimension Helpers";
        BatchHelpers: Codeunit "JB Batch Helpers";
        // dimension inputs
        ContractCode: Code[20];
        ContractName: Text[50];
        HaveContract: Boolean;
        ActPeriodCode: Code[20];
        ActPeriodName: Text[50];
        HaveActPeriod: Boolean;
        PostingTxt: Text;
        LinePostingDate: Date;
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

        // posting date precedence: line > default (set/top) > WorkDate
        LinePostingDate := 0D;
        if LineObj.Get('postingDate', Tok) and Tok.IsValue() then begin
            PostingTxt := Tok.AsValue().AsText();
            if Evaluate(LinePostingDate, PostingTxt) then
                GenJnlLine.Validate("Posting Date", LinePostingDate);
        end;
        if GenJnlLine."Posting Date" = 0D then begin
            if DefaultPostingDate <> 0D then
                GenJnlLine.Validate("Posting Date", DefaultPostingDate)
            else
                GenJnlLine.Validate("Posting Date", WorkDate());
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

        // ------- dimensions: string or { code, name } -------
        ParseDim(LineObj, 'contractCode', ContractCode, ContractName, HaveContract);
        ParseDim(LineObj, 'activityPeriod', ActPeriodCode, ActPeriodName, HaveActPeriod);

        if HaveContract or HaveActPeriod then
            DimHelper.ApplyContractAndActPeriodDims(GenJnlLine, ContractCode, ContractName, ActPeriodCode, ActPeriodName);

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

    // ---- helpers ----
    local procedure ParseDim(LineObj: JsonObject; FieldName: Text; var CodeOut: Code[20]; var NameOut: Text[50]; var Provided: Boolean)
    var
        Tok: JsonToken;
        Obj: JsonObject;
        V: JsonValue;
        CodeTxt: Text;
        NameTxt: Text;
    begin
        Provided := false;
        Clear(CodeOut);
        Clear(NameOut);

        if not LineObj.Get(FieldName, Tok) then
            exit;

        if Tok.IsValue() then begin
            V := Tok.AsValue();
            CodeTxt := V.AsText();
            if CodeTxt <> '' then begin
                CodeOut := CopyStr(CodeTxt, 1, MaxStrLen(CodeOut));
                Provided := true;
            end;
            exit;
        end;

        if Tok.IsObject() then begin
            Obj := Tok.AsObject();

            if Obj.Get('code', Tok) and Tok.IsValue() then begin
                CodeTxt := Tok.AsValue().AsText();
                if CodeTxt <> '' then begin
                    CodeOut := CopyStr(CodeTxt, 1, MaxStrLen(CodeOut));
                    Provided := true;
                end;
            end;

            if Obj.Get('name', Tok) and Tok.IsValue() then begin
                NameTxt := Tok.AsValue().AsText();
                if NameTxt <> '' then
                    NameOut := CopyStr(NameTxt, 1, MaxStrLen(NameOut));
            end;
        end;
    end;
}