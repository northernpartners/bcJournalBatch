codeunit 50105 "JB Dimension Helpers"
{
    procedure ApplyContractAndActPeriodDims(var GenJnlLine: Record "Gen. Journal Line"; ContractTxt: Text; ActPeriodTxt: Text)
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

    procedure EnsureDimensionValue(DimensionCode: Code[20]; DimValue: Code[20]; NameTxt: Text)
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
}