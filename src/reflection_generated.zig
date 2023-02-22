// ---
// TODO make this generated
// ---

/// New schema language features that are not supported by old code generators.
pub const AdvancedFeatures = enum(u4) {
    AdvancedArrayFeatures = 1,
    AdvancedUnionFeatures = 2,
    OptionalScalars = 4,
    DefaultVectorsAndStrings = 8,

    pub fn int(e: AdvancedFeatures) u4 {
        return @enumToInt(e);
    }
};
