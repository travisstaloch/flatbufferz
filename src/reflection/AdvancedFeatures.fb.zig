//!
//! generated by flatc-zig
//! binary:     gen/home/travis/Downloads/flatbuffers/reflection/reflection.bfbs
//! schema:     /home/travis/Downloads/flatbuffers/reflection/reflection.fbs
//! file ident: //reflection.fbs
//! typename    reflection.AdvancedFeatures
//!

const std = @import("std");
const fb = @import("flatbufferz");
const Builder = fb.Builder;

// a namespace generated by flatc-zig to match typenames produced by flatc
const reflection = struct {
    const AdvancedFeatures = @import("AdvancedFeatures.fb.zig").AdvancedFeatures;
};

/// New schema language features that are not supported by old code generators.
pub const AdvancedFeatures = enum(u64) {
    AdvancedArrayFeatures = 1,
    AdvancedUnionFeatures = 2,
    OptionalScalars = 4,
    DefaultVectorsAndStrings = 8,
    pub fn tagName(v: @This()) []const u8 {
        return @tagName(v);
    }
};
