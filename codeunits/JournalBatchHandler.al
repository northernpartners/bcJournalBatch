codeunit 50101 "Journal Batch Handler"
{
    [ServiceEnabled]
    procedure PostJournalBatch(requestBody: Text): Text
    var
        InObj: JsonObject;
        OutObj: JsonObject;
        OutTxt: Text;
        TemplateName: Code[10];
        BatchName: Code[10];
        BatchNameTok: JsonToken;
        LineSetsTok: JsonToken;
        LinesTok: JsonToken;
        ResultsArr: JsonArray;
        SingleSetObj: JsonObject;
    begin
        Clear(ResultsArr);
        TemplateName := 'BCINT';

        // Parse input
        if not InObj.ReadFrom(requestBody) then begin
            OutObj.Add('success', false);
            OutObj.Add('message', 'Invalid JSON in requestBody.');
            OutObj.WriteTo(OutTxt);
            exit(OutTxt);
        end;

        // Optional batchName; empty -> auto-create
        Clear(BatchName);
        if InObj.Get('batchName', BatchNameTok) and BatchNameTok.IsValue() then
            BatchName := CopyStr(BatchNameTok.AsValue().AsText(), 1, MaxStrLen(BatchName));

        // Ensure template+batch exist AND force No. Series = BCINT
        EnsureBatchExists(TemplateName, BatchName);
        EnsureBatchNoSeries(TemplateName, BatchName, 'BCINT');

        // Support EITHER lineSets[][] OR lines[]
        if InObj.Get('lineSets', LineSetsTok) and LineSetsTok.IsArray() then
            ResultsArr := HandleMultipleSets(LineSetsTok.AsArray(), TemplateName, BatchName)
        else begin
            if not InObj.Get('lines', LinesTok) then begin
                OutObj.Add('success', false);
                OutObj.Add('message', 'Provide either "lineSets" (array of sets) or "lines" (single set).');
                OutObj.Add('batchName', BatchName);
                OutObj.WriteTo(OutTxt);
                exit(OutTxt);
            end;
            if not LinesTok.IsArray() then begin
                OutObj.Add('success', false);
                OutObj.Add('message', '"lines" must be an array.');
                OutObj.Add('batchName', BatchName);
                OutObj.WriteTo(OutTxt);
                exit(OutTxt);
            end;

            // Build a synthetic lineSets = [ { lines: [...] } ]
            SingleSetObj.Add('lines', LinesTok.AsArray());
            ResultsArr := HandleSingleSet(SingleSetObj, TemplateName, BatchName);
        end;

        // Summarize
        AddSummaryAndWrite(ResultsArr, BatchName, OutTxt);
        exit(OutTxt);
    end;

    // ---------------- Core handlers ----------------

    local procedure HandleMultipleSets(LineSetsArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]): JsonArray
    var
        OutArr: JsonArray;
        SetTok: JsonToken;
        i: Integer;
        SetObj: JsonObject;
        OneSetArr: JsonArray;
        Tok2: JsonToken;
        ErrObj: JsonObject;
    begin
        Clear(OutArr);

        for i := 0 to LineSetsArr.Count() - 1 do begin
            LineSetsArr.Get(i, SetTok);

            if not SetTok.IsObject() then begin
                ErrObj.Add('success', false);
                ErrObj.Add('error', 'lineSets[' + Format(i) + '] is not an object. Expected {"lines":[...]}');
                OutArr.Add(ErrObj);
                Clear(ErrObj);
            end else begin
                SetObj := SetTok.AsObject();

                // HandleSingleSet returns an array with one object at index 0
                OneSetArr := HandleSingleSet(SetObj, TemplateName, BatchName);
                if OneSetArr.Count() > 0 then begin
                    OneSetArr.Get(0, Tok2);
                    if Tok2.IsObject() then
                        OutArr.Add(Tok2.AsObject())
                    else begin
                        ErrObj.Add('success', false);
                        ErrObj.Add('error', 'Internal error: unexpected result token.');
                        OutArr.Add(ErrObj);
                        Clear(ErrObj);
                    end;
                end;
            end;
        end;

        exit(OutArr);
    end;

    local procedure HandleSingleSet(SetObj: JsonObject; TemplateName: Code[10]; BatchName: Code[10]): JsonArray
    var
        LinesTok: JsonToken;
        LinesArr: JsonArray;
        ResArr: JsonArray;
        ResObj: JsonObject;
        ErrorsArr: JsonArray;
        i: Integer;
        LineTok: JsonToken;
        LineObj: JsonObject;
        insertedCnt: Integer;
        failedCnt: Integer;
        errTxt: Text;
        DocNo: Code[20];
    begin
        Clear(ResArr);
        Clear(ResObj);
        Clear(ErrorsArr);
        insertedCnt := 0;
        failedCnt := 0;

        if not SetObj.Get('lines', LinesTok) then begin
            ResObj.Add('success', false);
            ResObj.Add('error', 'Missing "lines" in set.');
            ResArr.Add(ResObj);
            exit(ResArr);
        end;
        if not LinesTok.IsArray() then begin
            ResObj.Add('success', false);
            ResObj.Add('error', '"lines" in set must be an array.');
            ResArr.Add(ResObj);
            exit(ResArr);
        end;

        LinesArr := LinesTok.AsArray();

        // Get next Document No. from batch No. Series (increments the series)
        DocNo := GetNextDocumentNo(TemplateName, BatchName);

        // Insert all lines in this set with the same Document No.
        for i := 0 to LinesArr.Count() - 1 do begin
            LinesArr.Get(i, LineTok);
            if not LineTok.IsObject() then begin
                AddError(ErrorsArr, i, 'Line is not a JSON object.');
                failedCnt += 1;
            end else begin
                LineObj := LineTok.AsObject();
                if BuildAndInsertLineWithDoc(LineObj, TemplateName, BatchName, DocNo) then
                    insertedCnt += 1
                else begin
                    errTxt := GetLastErrorText();
                    if errTxt = '' then errTxt := 'Unknown error while inserting line.';
                    AddError(ErrorsArr, i, errTxt);
                    failedCnt += 1;
                end;
            end;
        end;

        ResObj.Add('success', failedCnt = 0);
        ResObj.Add('documentNo', DocNo);
        ResObj.Add('insertedCount', insertedCnt);
        ResObj.Add('failedCount', failedCnt);
        ResObj.Add('failedLines', ErrorsArr);
        ResArr.Add(ResObj);
        exit(ResArr);
    end;

    local procedure AddSummaryAndWrite(ResultsArr: JsonArray; BatchName: Code[10]; var OutTxt: Text)
    var
        OutObj: JsonObject;
        i: Integer;
        Tok: JsonToken;
        SetObj: JsonObject;
        totalInserted: Integer;
        totalFailed: Integer;
    begin
        totalInserted := 0;
        totalFailed := 0;

        for i := 0 to ResultsArr.Count() - 1 do begin
            ResultsArr.Get(i, Tok);
            if Tok.IsObject() then begin
                SetObj := Tok.AsObject();
                totalInserted += GetIntFromObj(SetObj, 'insertedCount');
                totalFailed += GetIntFromObj(SetObj, 'failedCount');
            end;
        end;

        OutObj.Add('success', totalFailed = 0);
        OutObj.Add('batchName', BatchName);
        OutObj.Add('sets', ResultsArr);
        OutObj.Add('totalInserted', totalInserted);
        OutObj.Add('totalFailed', totalFailed);
        OutObj.WriteTo(OutTxt);
    end;

    // ---------------- Batch / No. Series helpers ----------------

    local procedure EnsureBatchExists(TemplateName: Code[10]; var BatchName: Code[10])
    var
        Batch: Record "Gen. Journal Batch";
        Tmpl: Record "Gen. Journal Template";
        NewName: Code[10];
    begin
        if not Tmpl.Get(TemplateName) then begin
            Tmpl.Init();
            Tmpl.Validate(Name, TemplateName);
            Tmpl.Validate(Type, Tmpl.Type::General);
            Tmpl.Insert(true);
        end;

        if (BatchName <> '') and Batch.Get(TemplateName, BatchName) then
            exit;

        NewName := MakeApiBatchName();
        Batch.Init();
        Batch.Validate("Journal Template Name", TemplateName);
        Batch.Validate(Name, NewName);
        Batch.Insert(true);

        BatchName := NewName;
    end;

    local procedure EnsureBatchNoSeries(TemplateName: Code[10]; BatchName: Code[10]; RequiredSeries: Code[20])
    var
        Batch: Record "Gen. Journal Batch";
    begin
        if not Batch.Get(TemplateName, BatchName) then
            Error('Batch %1/%2 not found after creation.', TemplateName, BatchName);

        if Batch."No. Series" <> RequiredSeries then begin
            Batch.Validate("No. Series", RequiredSeries);
            Batch.Modify(true);
        end;
    end;

    local procedure GetNextDocumentNo(TemplateName: Code[10]; BatchName: Code[10]): Code[20]
    var
        Batch: Record "Gen. Journal Batch";
        NoSeries: Codeunit "No. Series";
        NextNo: Code[20];
    begin
        if not Batch.Get(TemplateName, BatchName) then
            Error('Batch %1/%2 not found.', TemplateName, BatchName);

        if Batch."No. Series" = '' then
            Error('Batch %1/%2 has no No. Series. Assign a series first.', TemplateName, BatchName);

        NextNo := NoSeries.GetNextNo(Batch."No. Series", WorkDate());
        exit(NextNo);
    end;

    // ---------------- Line building ----------------

    [TryFunction]
    local procedure BuildAndInsertLineWithDoc(LineObj: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; DocNo: Code[20])
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
    begin
        GenJnlLine.Init();
        GenJnlLine.Validate("Journal Template Name", TemplateName);
        GenJnlLine.Validate("Journal Batch Name", BatchName);

        LineNo := GetNextLineNo(TemplateName, BatchName);
        GenJnlLine.Validate("Line No.", LineNo);

        // Assign Document No. for this set
        GenJnlLine.Validate("Document No.", DocNo);

        // documentType -> "Document Type" (enum)
        if LineObj.Get('documentType', Tok) and Tok.IsValue() then begin
            DocTypeTxt := UpperCase(Tok.AsValue().AsText());
            DocType := MapDocumentType(DocTypeTxt);
            GenJnlLine.Validate("Document Type", DocType);
        end;

        // documentDate -> "Document Date"
        if LineObj.Get('documentDate', Tok) and Tok.IsValue() then begin
            if not Evaluate(D, Tok.AsValue().AsText()) then
                Error('Invalid documentDate: %1', Tok.AsValue().AsText());
            GenJnlLine.Validate("Document Date", D);
        end;

        // postingDate -> "Posting Date"
        if LineObj.Get('postingDate', Tok) and Tok.IsValue() then begin
            if not Evaluate(D, Tok.AsValue().AsText()) then
                Error('Invalid postingDate: %1', Tok.AsValue().AsText());
            GenJnlLine.Validate("Posting Date", D);
        end;

        // accountType -> enum
        if LineObj.Get('accountType', Tok) and Tok.IsValue() then begin
            AccTypeTxt := UpperCase(Tok.AsValue().AsText());
            AccType := MapAccountType(AccTypeTxt);
            GenJnlLine.Validate("Account Type", AccType);
        end;

        // accountNo
        if LineObj.Get('accountNo', Tok) and Tok.IsValue() then
            GenJnlLine.Validate("Account No.", Tok.AsValue().AsText());

        // balanceAccountType alias OR balAccountType
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

        // balanceAccountNumber alias OR balAccountNo
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

        // externalDocumentNumber (alias) or externalDocumentNo (old)
        if LineObj.Get('externalDocumentNumber', Tok) and Tok.IsValue() then
            GenJnlLine.Validate("External Document No.", Tok.AsValue().AsText())
        else
            if LineObj.Get('externalDocumentNo', Tok) and Tok.IsValue() then
                GenJnlLine.Validate("External Document No.", Tok.AsValue().AsText());

        // contractCode / activityPeriod -> dimensions (auto-create values if missing)
        ContractTxt := '';
        ActPeriodTxt := '';
        if LineObj.Get('contractCode', Tok) and Tok.IsValue() then
            ContractTxt := Tok.AsValue().AsText();
        if LineObj.Get('activityPeriod', Tok) and Tok.IsValue() then
            ActPeriodTxt := Tok.AsValue().AsText();

        if (ContractTxt <> '') or (ActPeriodTxt <> '') then
            ApplyContractAndActPeriodDims(GenJnlLine, ContractTxt, ActPeriodTxt);

        GenJnlLine.Insert(true);
    end;

    // ---------------- Small utils ----------------

    local procedure ApplyContractAndActPeriodDims(var GenJnlLine: Record "Gen. Journal Line"; ContractTxt: Text; ActPeriodTxt: Text)
    var
        TempDimSet: Record "Dimension Set Entry" temporary;
        DimMgt: Codeunit DimensionManagement;
        NewId: Integer;
        Code20: Code[20];
    begin
        Clear(TempDimSet);

        if ContractTxt <> '' then begin
            Code20 := CopyStr(ContractTxt, 1, MaxStrLen(Code20));
            EnsureDimensionValue('CONTRACT', Code20, ContractTxt);
            TempDimSet.Init();
            TempDimSet.Validate("Dimension Code", 'CONTRACT');
            TempDimSet.Validate("Dimension Value Code", Code20);
            TempDimSet.Insert();
        end;

        if ActPeriodTxt <> '' then begin
            Code20 := CopyStr(ActPeriodTxt, 1, MaxStrLen(Code20));
            EnsureDimensionValue('ACTPERIOD', Code20, ActPeriodTxt);
            TempDimSet.Init();
            TempDimSet.Validate("Dimension Code", 'ACTPERIOD');
            TempDimSet.Validate("Dimension Value Code", Code20);
            TempDimSet.Insert();
        end;

        if not TempDimSet.IsEmpty() then begin
            NewId := DimMgt.GetDimensionSetID(TempDimSet);
            GenJnlLine."Dimension Set ID" := NewId;
        end;
    end;

    local procedure EnsureDimensionValue(DimensionCode: Code[20]; DimValue: Code[20]; NameTxt: Text)
    var
        DimVal: Record "Dimension Value";
        Name50: Text[50];
    begin
        if DimValue = '' then
            exit;

        Name50 := CopyStr(NameTxt, 1, MaxStrLen(Name50));

        if not DimVal.Get(DimensionCode, DimValue) then begin
            DimVal.Init();
            DimVal.Validate("Dimension Code", DimensionCode);
            DimVal.Validate(Code, DimValue);
            DimVal.Validate(Name, Name50);
            DimVal.Insert(true);
        end else begin
            if (TrimText(DimVal.Name) = '') or (UpperCase(TrimText(DimVal.Name)) = 'AUTOCREATED') then begin
                DimVal.Name := Name50;
                DimVal.Modify(false);
            end;
        end;
    end;

    local procedure TrimText(T: Text): Text
    begin
        exit(DelChr(T, '<>', ' '));
    end;

    local procedure AddError(var ErrorsArr: JsonArray; Index: Integer; Msg: Text)
    var
        ErrObj: JsonObject;
    begin
        ErrObj.Add('index', Index);
        ErrObj.Add('error', Msg);
        ErrorsArr.Add(ErrObj);
    end;

    local procedure GetNextLineNo(TemplateName: Code[10]; BatchName: Code[10]): Integer
    var
        L: Record "Gen. Journal Line";
    begin
        L.Reset();
        L.SetRange("Journal Template Name", TemplateName);
        L.SetRange("Journal Batch Name", BatchName);
        L.SetCurrentKey("Journal Template Name", "Journal Batch Name", "Line No.");
        if L.FindLast() then
            exit(L."Line No." + 10000)
        else
            exit(10000);
    end;

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

    local procedure GetIntFromObj(Obj: JsonObject; FieldName: Text): Integer
    var
        Tok: JsonToken;
    begin
        if Obj.Get(FieldName, Tok) and Tok.IsValue() then
            exit(Tok.AsValue().AsInteger());
        exit(0);
    end;

    // Generate a compact Code[10] from GUID, prefixed 'API'
    local procedure MakeApiBatchName(): Code[10]
    var
        g: Guid;
        s: Text;
    begin
        g := CreateGuid();
        s := DelChr(Format(g), '=', '{}-');
        exit(CopyStr('API' + UpperCase(s), 1, 10));
    end;
}