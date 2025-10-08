codeunit 50114 "Journal Batch Handler"
{
    [ServiceEnabled]
    procedure PostJournalBatch(requestBody: Text): Text
    var
        InObj: JsonObject;
        OutTxt: Text;
        TemplateName: Code[10];
        BatchName: Code[10];
        BatchNameTok: JsonToken;
        LineSetsTok: JsonToken;
        LinesTok: JsonToken;
        ResultsArr: JsonArray;
        Core: Codeunit "JB Core";
        BatchHelpers: Codeunit "JB Batch Helpers";
        TopPostingDate: Date;
        PostingTok: JsonToken;
        PostingTxt: Text;
    begin
        TemplateName := 'GENERAL';
        Clear(ResultsArr);
        TopPostingDate := 0D;

        if not InObj.ReadFrom(requestBody) then
            exit(Core.MakeError('Invalid JSON in requestBody.'));

        // optional batchName; empty -> auto-create
        Clear(BatchName);
        if InObj.Get('batchName', BatchNameTok) and BatchNameTok.IsValue() then
            BatchName := CopyStr(BatchNameTok.AsValue().AsText(), 1, MaxStrLen(BatchName));

        // top-level postingDate
        if InObj.Get('postingDate', PostingTok) and PostingTok.IsValue() then begin
            PostingTxt := PostingTok.AsValue().AsText();
            if not Evaluate(TopPostingDate, PostingTxt) then
                TopPostingDate := 0D; // ignore invalid -> will fall back later
        end;

        // ensure template + batch, and force No. Series = SALPAYOUT
        BatchHelpers.EnsureBatchExists(TemplateName, BatchName);
        BatchHelpers.EnsureBatchNoSeries(TemplateName, BatchName, 'SALPAYOUT');

        // Either lineSets[] or lines[]
        if InObj.Get('lineSets', LineSetsTok) and LineSetsTok.IsArray() then
            ResultsArr := Core.HandleMultipleSets(LineSetsTok.AsArray(), TemplateName, BatchName, TopPostingDate)
        else begin
            if not (InObj.Get('lines', LinesTok) and LinesTok.IsArray()) then
                exit(Core.MakeSimpleResponse(false, BatchName, 'Provide either "lineSets" (array of sets) or "lines" (single set).'));
            ResultsArr := Core.HandleSingleSetAsArray(LinesTok.AsArray(), TemplateName, BatchName, TopPostingDate);
        end;

        OutTxt := Core.BuildSummary(ResultsArr, BatchName);
        exit(OutTxt);
    end;
}