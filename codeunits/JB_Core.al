codeunit 50102 "JB Core"
{
    procedure HandleMultipleSets(LineSetsArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]): JsonArray
    var
        OutArr: JsonArray;
        SetTok: JsonToken;
        i: Integer;
        OneObj: JsonObject;
        LinesTok: JsonToken;
    begin
        Clear(OutArr);

        for i := 0 to LineSetsArr.Count() - 1 do begin
            LineSetsArr.Get(i, SetTok);

            Clear(OneObj);
            if not SetTok.IsObject() then begin
                OneObj.Add('success', false);
                OneObj.Add('error', 'lineSets[' + Format(i) + '] is not an object. Expected {"lines":[...]}');
                OutArr.Add(OneObj);
            end else begin
                if not SetTok.AsObject().Get('lines', LinesTok) then begin
                    OneObj.Add('success', false);
                    OneObj.Add('error', 'Missing "lines" in set at index ' + Format(i));
                    OutArr.Add(OneObj);
                end else
                    OutArr.Add(HandleOneSet(LinesTok.AsArray(), TemplateName, BatchName));
            end;
        end;

        exit(OutArr);
    end;

    // Back-compat: single set via "lines": [...]
    procedure HandleSingleSetAsArray(LinesArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]): JsonArray
    var
        OutArr: JsonArray;
    begin
        OutArr.Add(HandleOneSet(LinesArr, TemplateName, BatchName));
        exit(OutArr);
    end;

    procedure BuildSummary(ResultsArr: JsonArray; BatchName: Code[10]): Text
    var
        OutObj: JsonObject;
        Tok: JsonToken;
        SetObj: JsonObject;
        i: Integer;
        totalInserted: Integer;
        totalFailed: Integer;
        OutTxt: Text;
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
        exit(OutTxt);
    end;

    procedure MakeError(MessageTxt: Text): Text
    var
        O: JsonObject;
        T: Text;
    begin
        O.Add('success', false);
        O.Add('message', MessageTxt);
        O.WriteTo(T);
        exit(T);
    end;

    procedure MakeSimpleResponse(Success: Boolean; BatchName: Code[10]; MessageTxt: Text): Text
    var
        O: JsonObject;
        T: Text;
    begin
        O.Add('success', Success);
        O.Add('batchName', BatchName);
        O.Add('message', MessageTxt);
        O.WriteTo(T);
        exit(T);
    end;

    // ------------ private ------------
    local procedure HandleOneSet(LinesArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]): JsonObject
    var
        BatchHelpers: Codeunit "JB Batch Helpers";
        LineBuilder: Codeunit "JB Line Builder";
        ResObj: JsonObject;
        ErrorsArr: JsonArray;
        DocNo: Code[20];
        i: Integer;
        LineTok: JsonToken;
        LineObj: JsonObject;
        ok: Boolean;
        errTxt: Text;
        insertedCnt: Integer;
        failedCnt: Integer;
    begin
        Clear(ResObj);
        Clear(ErrorsArr);
        insertedCnt := 0;
        failedCnt := 0;

        // one doc no. per set (consumes the series)
        DocNo := BatchHelpers.GetNextDocumentNo(TemplateName, BatchName);

        for i := 0 to LinesArr.Count() - 1 do begin
            LinesArr.Get(i, LineTok);
            if not LineTok.IsObject() then begin
                AddError(ErrorsArr, i, 'Line is not a JSON object.');
                failedCnt += 1;
            end else begin
                LineObj := LineTok.AsObject();
                ok := LineBuilder.InsertLineWithDoc(LineObj, TemplateName, BatchName, DocNo);
                if ok then
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
        exit(ResObj);
    end;

    local procedure AddError(var ErrorsArr: JsonArray; Index: Integer; Msg: Text)
    var
        ErrObj: JsonObject;
    begin
        ErrObj.Add('index', Index);
        ErrObj.Add('error', Msg);
        ErrorsArr.Add(ErrObj);
    end;

    local procedure GetIntFromObj(Obj: JsonObject; FieldName: Text): Integer
    var
        Tok: JsonToken;
    begin
        if Obj.Get(FieldName, Tok) and Tok.IsValue() then
            exit(Tok.AsValue().AsInteger());
        exit(0);
    end;
}