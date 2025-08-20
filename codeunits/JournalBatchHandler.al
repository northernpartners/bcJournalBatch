codeunit 50101 "Journal Batch Handler"
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
    begin
        TemplateName := 'BCINT';
        Clear(ResultsArr);

        if not InObj.ReadFrom(requestBody) then
            exit(Core.MakeError('Invalid JSON in requestBody.'));

        // optional batchName; empty -> auto-create
        Clear(BatchName);
        if InObj.Get('batchName', BatchNameTok) and BatchNameTok.IsValue() then
            BatchName := CopyStr(BatchNameTok.AsValue().AsText(), 1, MaxStrLen(BatchName));

        // ensure template + batch, and force No. Series = BCINT
        BatchHelpers.EnsureBatchExists(TemplateName, BatchName);
        BatchHelpers.EnsureBatchNoSeries(TemplateName, BatchName, 'BCINT');

        // Either lineSets[] or lines[]
        if InObj.Get('lineSets', LineSetsTok) and LineSetsTok.IsArray() then
            ResultsArr := Core.HandleMultipleSets(LineSetsTok.AsArray(), TemplateName, BatchName)
        else begin
            if not (InObj.Get('lines', LinesTok) and LinesTok.IsArray()) then
                exit(Core.MakeSimpleResponse(false, BatchName, 'Provide either "lineSets" (array of sets) or "lines" (single set).'));
            ResultsArr := Core.HandleSingleSetAsArray(LinesTok.AsArray(), TemplateName, BatchName);
        end;

        OutTxt := Core.BuildSummary(ResultsArr, BatchName);
        exit(OutTxt);
    end;
}