codeunit 50102 "JB Core"
{
    procedure HandleMultipleSets(LineSetsArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]; TopPostingDate: Date): JsonArray
    var
        OutArr: JsonArray;
        SetTok: JsonToken;
        i: Integer;
        SetObj: JsonObject;
        LinesTok: JsonToken;
        DefaultPostingDate: Date;
        SetPostingTok: JsonToken;
        SetPostingTxt: Text;
        SetPostingDate: Date;
    begin
        Clear(OutArr);

        for i := 0 to LineSetsArr.Count() - 1 do begin
            LineSetsArr.Get(i, SetTok);

            if not SetTok.IsObject() then begin
                OutArr.Add(MakeSetError('lineSets[' + Format(i) + '] is not an object. Expected {"lines":[...]}'));
            end else begin
                SetObj := SetTok.AsObject();

                if not SetObj.Get('lines', LinesTok) then begin
                    OutArr.Add(MakeSetError('Missing "lines" in set at index ' + Format(i)));
                end else begin
                    // set-level postingDate (optional)
                    SetPostingDate := 0D;
                    if SetObj.Get('postingDate', SetPostingTok) and SetPostingTok.IsValue() then begin
                        SetPostingTxt := SetPostingTok.AsValue().AsText();
                        if not Evaluate(SetPostingDate, SetPostingTxt) then
                            SetPostingDate := 0D;
                    end;

                    // precedence for default: set > top (line-level handled in Line Builder)
                    if SetPostingDate <> 0D then
                        DefaultPostingDate := SetPostingDate
                    else
                        DefaultPostingDate := TopPostingDate;

                    OutArr.Add(HandleOneSet(LinesTok.AsArray(), TemplateName, BatchName, DefaultPostingDate));
                end;
            end;
        end;

        exit(OutArr);
    end;

    // Back-compat: single set via "lines": [...]
    procedure HandleSingleSetAsArray(LinesArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]; TopPostingDate: Date): JsonArray
    var
        OutArr: JsonArray;
    begin
        OutArr.Add(HandleOneSet(LinesArr, TemplateName, BatchName, TopPostingDate));
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
    local procedure HandleOneSet(LinesArr: JsonArray; TemplateName: Code[10]; BatchName: Code[10]; DefaultPostingDate: Date): JsonObject
    var
        BatchHelpers: Codeunit "JB Batch Helpers";
        LineBuilder: Codeunit "JB Line Builder";
        ResObj: JsonObject;
        ErrorsArr: JsonArray;
        ExternalIdsArr: JsonArray;
        DocNo: Code[20];
        i: Integer;
        LineTok: JsonToken;
        LineObj: JsonObject;
        ok: Boolean;
        errTxt: Text;
        insertedCnt: Integer;
        failedCnt: Integer;
        ExternalId: Text;
        JVal: JsonValue;
        IdInt: Integer;
    begin
        Clear(ResObj);
        Clear(ErrorsArr);
        Clear(ExternalIdsArr);
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
                ExternalId := '';
                ok := LineBuilder.InsertLineWithDoc(LineObj, TemplateName, BatchName, DocNo, DefaultPostingDate, ExternalId);
                if ok then begin
                    insertedCnt += 1;
                    if ExternalId <> '' then begin
                        if Evaluate(IdInt, ExternalId) then
                            JVal.SetValue(IdInt)
                        else
                            JVal.SetValue(ExternalId);
                        ExternalIdsArr.Add(JVal);
                        Clear(JVal);
                    end;
                end else begin
                    errTxt := GetLastErrorText();
                    if errTxt = '' then errTxt := 'Unknown error while inserting line.';
                    AddErrorWithId(ErrorsArr, i, errTxt, ExternalId);
                    failedCnt += 1;
                end;
            end;
        end;

        ResObj.Add('success', failedCnt = 0);
        ResObj.Add('documentNo', DocNo);
        ResObj.Add('insertedCount', insertedCnt);
        ResObj.Add('externalIds', ExternalIdsArr); // NEW
        ResObj.Add('failedCount', failedCnt);
        ResObj.Add('failedLines', ErrorsArr);
        exit(ResObj);
    end;

    local procedure MakeSetError(Msg: Text): JsonObject
    var
        O: JsonObject;
    begin
        O.Add('success', false);
        O.Add('error', Msg);
        exit(O);
    end;

    local procedure AddError(var ErrorsArr: JsonArray; Index: Integer; Msg: Text)
    var
        ErrObj: JsonObject;
    begin
        ErrObj.Add('index', Index);
        ErrObj.Add('error', Msg);
        ErrorsArr.Add(ErrObj);
    end;

    local procedure AddErrorWithId(var ErrorsArr: JsonArray; Index: Integer; Msg: Text; ExternalId: Text)
    var
        ErrObj: JsonObject;
        IdInt: Integer;
    begin
        ErrObj.Add('index', Index);
        if ExternalId <> '' then begin
            if Evaluate(IdInt, ExternalId) then
                ErrObj.Add('id', IdInt)
            else
                ErrObj.Add('id', ExternalId);
        end;
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