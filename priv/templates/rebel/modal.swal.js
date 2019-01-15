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
  let query_output = {};
  if (result.value) {
    query_output = [window.rebel_modal.sender, {
      method: 'confirm',
      result: result.value
    }];
  } else {
    query_output = [window.rebel_modal.sender, {
      method: 'cancel',
      result: result
    }];
  }
  window.Rebel.return_channel.push("modal", { ok: query_output });
});
<% else %>
.then(() => {
    console.log('no confirm function');
    swal.close();
});
<% end %>
