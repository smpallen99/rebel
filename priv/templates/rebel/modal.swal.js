<% type_val = if type, do: "type: '#{type}',", else: nil %>
swal({
  title: '<%= title %>',
  text: '<%= text %>',
  <%= type_val %>
  <%= for {k, v} <- opts do %>
  <%= "#{k}: #{v}" %>,
  <% end %>
})
<%= if confirm_function do %>
.then((result) => {
  if (result.value) {
    let query_output = [window.rebel_modal.sender, {
      method: 'confirm',
      result: result.value
    }];
    window.Rebel.return_channel.push("modal", { ok: query_output });
  } else {
    let query_output = [window.rebel_modal.sender, {
      method: 'cancel',
      result: result
    }];
    window.Rebel.return_channel.push("modal", { ok: query_output });
  }
});
<% end %>
