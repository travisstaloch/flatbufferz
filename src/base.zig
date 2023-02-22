pub const file_identifier_length = 4;

/// Computes how many bytes you'd have to pad to be able to write an
/// "scalar_size" scalar if the buffer had grown to "buf_size" (downwards in
/// memory).
/// __suppress_ubsan__("unsigned-integer-overflow")
pub fn paddingBytes(buf_size: usize, scalar_size: usize) usize {
    return ((~buf_size) +% 1) & (scalar_size -% 1);
}

pub const FLATBUFFERS_MAX_ALIGNMENT = 32;

pub fn verifyAlignmentRequirements(align_: usize, opts: struct { min_align: usize = 1 }) bool {
    return (opts.min_align <= align_) and (align_ <= FLATBUFFERS_MAX_ALIGNMENT) and
        (align_ & (align_ - 1)) == 0; // must be power of 2
}
