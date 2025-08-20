codeunit 50105 "JB Dimension Helpers"
{
    procedure ApplyContractAndActPeriodDims(var GenJnlLine: Record "Gen. Journal Line"; ContractCode: Code[20]; ContractName: Text[50]; ActPeriodCode: Code[20]; ActPeriodName: Text[50])
    var
        AddedAny: Boolean;
    begin
        AddedAny := false;

        if ContractCode <> '' then begin
            EnsureDimensionValue('CONTRACT', ContractCode, ContractName);
            ApplyOneDim(GenJnlLine, 'CONTRACT', ContractCode);
            AddedAny := true;
        end;

        if ActPeriodCode <> '' then begin
            EnsureDimensionValue('ACTPERIOD', ActPeriodCode, ActPeriodName);
            ApplyOneDim(GenJnlLine, 'ACTPERIOD', ActPeriodCode);
            AddedAny := true;
        end;

        // nothing else to do here; ApplyOneDim either used ShortcutDimN (best)
        // or merged Dimension Set ID while preserving existing dims
    end;

    // Ensure dim value exists (create/update name if blank/'AutoCreated')
    procedure EnsureDimensionValue(DimensionCode: Code[20]; DimValue: Code[20]; NameTxt: Text[50])
    var
        DimVal: Record "Dimension Value";
        Name50: Text[50];
    begin
        if DimValue = '' then
            exit;

        Name50 := NameTxt;

        if not DimVal.Get(DimensionCode, DimValue) then begin
            DimVal.Init();
            DimVal.Validate("Dimension Code", DimensionCode);
            DimVal.Validate(Code, DimValue);
            if Name50 <> '' then
                DimVal.Validate(Name, Name50);
            DimVal.Insert(true);
        end else begin
            if (UpperCase(DelChr(DimVal.Name, '<>', ' ')) = 'AUTOCREATED') and (Name50 <> '') then begin
                DimVal.Name := Name50;
                DimVal.Modify(false);
            end;
        end;
    end;

    // Applies a single dimension to the line:
    // 1) If the dimension code is mapped to a Shortcut Dimension N (1..8),
    //    call ValidateShortcutDimCode(N, value) so the visible "Contract Code"/"Activity period" fields are set.
    // 2) Otherwise, merge into the Dimension Set ID without losing existing dims.
    local procedure ApplyOneDim(var GenJnlLine: Record "Gen. Journal Line"; DimCode: Code[20]; DimValue: Code[20])
    var
        N: Integer;
        TempExisting: Record "Dimension Set Entry" temporary;
        TempAdd: Record "Dimension Set Entry" temporary;
        DimMgt: Codeunit DimensionManagement;
        NewId: Integer;
    begin
        if DimValue = '' then
            exit;

        N := GetShortcutIndexForDimension(DimCode);
        if N > 0 then begin
            GenJnlLine.ValidateShortcutDimCode(N, DimValue);
            exit;
        end;

        // Not mapped to any ShortcutDim => merge Dimension Set ID
        if GenJnlLine."Dimension Set ID" <> 0 then
            DimMgt.GetDimensionSet(TempExisting, GenJnlLine."Dimension Set ID");

        TempAdd.Init();
        TempAdd.Validate("Dimension Code", DimCode);
        TempAdd.Validate("Dimension Value Code", DimValue);
        TempAdd.Insert();

        // Merge: overlay TempAdd on TempExisting (replace if same code already present)
        if not TempExisting.IsEmpty() then begin
            // Replace-or-add
            if TempExisting.Get(GenJnlLine."Dimension Set ID", DimCode) then begin
                TempExisting.Validate("Dimension Value Code", DimValue);
                TempExisting.Modify();
            end else begin
                TempAdd."Dimension Set ID" := GenJnlLine."Dimension Set ID";
                TempAdd.Insert();
            end;
            NewId := DimMgt.GetDimensionSetID(TempExisting);
        end else
            NewId := DimMgt.GetDimensionSetID(TempAdd);

        GenJnlLine."Dimension Set ID" := NewId;
    end;

    // Returns 1..8 if the provided Dimension Code is mapped to a Shortcut Dimension N
    local procedure GetShortcutIndexForDimension(DimCode: Code[20]): Integer
    var
        GLSetup: Record "General Ledger Setup";
        i: Integer;
        CodeTxt: Code[20];
    begin
        if not GLSetup.Get() then
            exit(0);

        // Check Shortcut Dimension 1..8
        for i := 1 to 8 do begin
            CodeTxt := GetShortcutDimCode(GLSetup, i);
            if UpperCase(Format(CodeTxt)) = UpperCase(Format(DimCode)) then
                exit(i);
        end;

        exit(0);
    end;

    local procedure GetShortcutDimCode(GLSetup: Record "General Ledger Setup"; Index: Integer): Code[20]
    begin
        case Index of
            1:
                exit(GLSetup."Shortcut Dimension 1 Code");
            2:
                exit(GLSetup."Shortcut Dimension 2 Code");
            3:
                exit(GLSetup."Shortcut Dimension 3 Code");
            4:
                exit(GLSetup."Shortcut Dimension 4 Code");
            5:
                exit(GLSetup."Shortcut Dimension 5 Code");
            6:
                exit(GLSetup."Shortcut Dimension 6 Code");
            7:
                exit(GLSetup."Shortcut Dimension 7 Code");
            8:
                exit(GLSetup."Shortcut Dimension 8 Code");
        end;
        exit('');
    end;
}