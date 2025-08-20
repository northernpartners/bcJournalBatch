codeunit 50104 "JB Batch Helpers"
{
    procedure EnsureBatchExists(TemplateName: Code[10]; var BatchName: Code[10])
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

    procedure EnsureBatchNoSeries(TemplateName: Code[10]; BatchName: Code[10]; RequiredSeries: Code[20])
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

    procedure GetNextDocumentNo(TemplateName: Code[10]; BatchName: Code[10]): Code[20]
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

    procedure GetNextLineNo(TemplateName: Code[10]; BatchName: Code[10]): Integer
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

    procedure MakeApiBatchName(): Code[10]
    var
        g: Guid;
        s: Text;
    begin
        g := CreateGuid();
        s := DelChr(Format(g), '=', '{}-');
        exit(CopyStr('API' + UpperCase(s), 1, 10));
    end;
}