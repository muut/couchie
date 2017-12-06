defmodule Couchie.Transcoder do
  use Bitwise

  # When editing documents in the Couchbase Web UI 4.x flags are changed to 0x01.
  # We're going to treat it as JSON data. Better ideas welcome.
  @gui_legacy 0x01

  @json_flag 0x02 <<< 24
  @json_flag_legacy 0x02

  @raw_flag  0x03 <<< 24
  @raw_flag_legacy 0x04

  @str_flag  0x04 <<< 24
  @str_flag_legacy 0x08

  # When a document is created in the Couchbase Web UI 5.x flags are set to 0x02_000006
  # which is @json_flag + @json_flag_legacy + @str_flag_legacy.
  # So it seems safe to assume that if a modern type is not 0, legacy part must be ignored.
  #
  # Also a combination of legacy flags is quite confusing. How can a value be encoded as JSON and
  # a string simultaneously? It feels safer to drop support for such possibly erroneous data.
  #
  # From https://developer.couchbase.com/documentation/server/current/sdk/nonjson.html
  #    One of the metadata fields is a 32 bit "flag" value.
  #    all legacy typecodes (regardless of language) are under 24 bits in width

  # Modern flags mask
  @flag_mask 0xFF_00_00_00

  # API defined by cberl_transcoder.erl

  # Encoder

  # As described earlier there is no sense in combining json and raw or string,
  # so only one encoder is supported.

  def encode_value(encoder, value) do
    # In parallel to the call to this function cberl uses exported `flag/1` to
    # obtain the type descriptor of the encoded value. So to ensure that flag is
    # synchronized with the actual encoding `flag/1`should also be used here.
    #
    # A better way would be if this function returned both the type descriptor
    # and the encoded value, but cberl must be upgraded for that.
    do_encode_value(flag(encoder), value)
  end

  defp do_encode_value(flag, value) when flag === @json_flag do
    Poison.encode!(value)
  end

  defp do_encode_value(flag, value) when flag === @str_flag do
    value
  end

  defp do_encode_value(flag, value) when flag === @raw_flag do
    :erlang.term_to_binary(value)
  end


  # Decoder

  def decode_value(flag, value) when (flag &&& @flag_mask) === @json_flag
  or flag === @json_flag_legacy
  or flag === (@json_flag_legacy + @str_flag_legacy)
  or flag === @gui_legacy do
    Poison.decode!(value)
  end

  def decode_value(flag, value) when (flag &&& @flag_mask) === @str_flag
  or flag === @str_flag_legacy do
    value
  end

  def decode_value(flag, value) when (flag &&& @flag_mask) === @raw_flag or flag === @raw_flag_legacy do
    # The doc says following on RAW flag:
    # Indicates this value is a raw sequence of bytes. It is the simplest encoding form and
    # indicates that the application will process and interpret its contents as it sees fit.
    #
    # I strongly suspect this shall be the same as @raw_str, however this might be needed for
    # backwards compatibility. Also term_to_binary is unsafe and can cause atom table overflow,
    # so this should be decided on the application level, not in the library.

    :erlang.binary_to_term(value)
  end


  def flag(encoder) do
    case encoder do
      :standard -> @json_flag
      :json -> @json_flag
      :raw_binary -> @raw_flag
      :str -> @str_flag
    end
  end

end
