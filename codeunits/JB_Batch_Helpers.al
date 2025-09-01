codeunit 50104 "JB Batch Helpers"
{
    procedure EnsureBatchExists(TemplateName: Code[10]; var BatchName: Code[10])
    var
        GenJnlBatch: Record "Gen. Journal Batch";
        UseName: Code[10];
    begin
        // If a batch name was supplied, try to use it (sanitized to Code[10]).
        if BatchName <> '' then begin
            UseName := SanitizeBatchName(BatchName);

            if UseName = '' then
                UseName := GenerateApiBatchName();

            // If batch with this name already exists under the template, we are done.
            GenJnlBatch.Reset();
            GenJnlBatch.SetRange("Journal Template Name", TemplateName);
            GenJnlBatch.SetRange(Name, UseName);
            if not GenJnlBatch.FindFirst() then begin
                // Create new batch with requested/sanitized name
                Clear(GenJnlBatch);
                GenJnlBatch.Init();
                GenJnlBatch.Validate("Journal Template Name", TemplateName);
                GenJnlBatch.Validate(Name, UseName);
                GenJnlBatch.Insert(true);
            end;

            BatchName := UseName;
            exit;
        end;

        // No batch name supplied -> create an APIxxxxx batch
        UseName := GenerateApiBatchName();

        Clear(GenJnlBatch);
        GenJnlBatch.Init();
        GenJnlBatch.Validate("Journal Template Name", TemplateName);
        GenJnlBatch.Validate(Name, UseName);
        GenJnlBatch.Insert(true);

        BatchName := UseName;
    end;

    procedure EnsureBatchNoSeries(TemplateName: Code[10]; BatchName: Code[10]; NoSeriesCode: Code[20])
    var
        GenJnlBatch: Record "Gen. Journal Batch";
    begin
        if NoSeriesCode = '' then
            exit;

        GenJnlBatch.Reset();
        GenJnlBatch.SetRange("Journal Template Name", TemplateName);
        GenJnlBatch.SetRange(Name, BatchName);
        if GenJnlBatch.FindFirst() then begin
            if GenJnlBatch."No. Series" <> NoSeriesCode then begin
                GenJnlBatch.Validate("No. Series", NoSeriesCode);
                GenJnlBatch.Modify(true);
            end;
        end;
    end;

    procedure GetNextDocumentNo(TemplateName: Code[10]; BatchName: Code[10]) DocNo: Code[20]
    var
        GenJnlBatch: Record "Gen. Journal Batch";
        NoSeries: Codeunit "No. Series";
        UsageDate: Date;
    begin
        GenJnlBatch.Reset();
        GenJnlBatch.SetRange("Journal Template Name", TemplateName);
        GenJnlBatch.SetRange(Name, BatchName);
        if not GenJnlBatch.FindFirst() then
            Error('Batch %1 under template %2 not found.', BatchName, TemplateName);

        if GenJnlBatch."No. Series" = '' then
            Error('Batch %1 has no "No. Series" assigned.', BatchName);

        UsageDate := WorkDate();
        DocNo := NoSeries.GetNextNo(GenJnlBatch."No. Series", UsageDate);
        if DocNo = '' then
            Error('Unable to retrieve next number from No. Series %1.', GenJnlBatch."No. Series");
    end;

    procedure GetNextLineNo(TemplateName: Code[10]; BatchName: Code[10]) NextNo: Integer
    var
        GenJnlLine: Record "Gen. Journal Line";
    begin
        GenJnlLine.Reset();
        GenJnlLine.SetRange("Journal Template Name", TemplateName);
        GenJnlLine.SetRange("Journal Batch Name", BatchName);
        if GenJnlLine.FindLast() then
            exit(GenJnlLine."Line No." + 10000)
        else
            exit(10000);
    end;

    // --------- helpers ---------

    local procedure SanitizeBatchName(InputName: Text): Code[10]
    var
        T: Text;
    begin
        T := UpperCase(InputName);
        // Remove spaces; add further sanitization if needed
        T := DelChr(T, '=', ' ');
        exit(CopyStr(T, 1, 10)); // field is Code[10]
    end;

    local procedure GenerateApiBatchName(): Code[10]
    var
        G: Guid;
        T: Text;
        Suffix: Text;
    begin
        // Use GUID, strip braces and hyphens, take first 7 chars after 'API'
        G := CreateGuid();
        T := Format(G);
        // remove '{', '}', '-' characters
        T := DelChr(T, '=', '{}-');
        Suffix := CopyStr(UpperCase(T), 1, 7);
        exit(CopyStr('API' + Suffix, 1, 10));
    end;
}