defmodule Jidoka.MessagingTest do
  use ExUnit.Case, async: true

  describe "session room mapping" do
    test "returns the same room for repeated session lookups" do
      session_id = "messaging_room_#{System.unique_integer([:positive, :monotonic])}"

      assert {:ok, room_a} = Jidoka.Messaging.ensure_room_for_session(session_id)
      assert {:ok, room_b} = Jidoka.Messaging.ensure_room_for_session(session_id)
      assert room_a.id == room_b.id

      assert {:ok, room_id} = Jidoka.Messaging.session_room_id(session_id)
      assert room_id == room_a.id
    end
  end

  describe "session message persistence" do
    test "appends and lists messages for a session room" do
      session_id = "messaging_msgs_#{System.unique_integer([:positive, :monotonic])}"

      assert {:ok, user_msg} =
               Jidoka.Messaging.append_session_message(session_id, :user, "hello from user")

      assert {:ok, assistant_msg} =
               Jidoka.Messaging.append_session_message(
                 session_id,
                 :assistant,
                 "hello from assistant"
               )

      assert user_msg.room_id == assistant_msg.room_id

      assert {:ok, messages} = Jidoka.Messaging.list_session_messages(session_id)

      ids = Enum.map(messages, & &1.id)
      assert user_msg.id in ids
      assert assistant_msg.id in ids
    end
  end
end
