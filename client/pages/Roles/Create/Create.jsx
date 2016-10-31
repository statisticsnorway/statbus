import React from 'react'
import { Button, Form, Message } from 'semantic-ui-react'

export default ({ submitRole, message, status }) => {
  const handleSubmit = (e, serialized) => {
    e.preventDefault()
    submitRole(serialized)
  }
  return (
    <Form onSubmit={handleSubmit}>
      <Form.Field>
        <label htmlFor="roleNameInput">Role name</label>
        <input
          id="roleNameInput"
          placeholder="e.g. Web Site Visitor"
          name="name"
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="roleDescriptionInput">Description</label>
        <input
          id="roleDescriptionInput"
          placeholder="e.g. Ordinary website user"
          name="description"
        />
      </Form.Field>
      <Button type="submit" primary>Submit</Button>
      {message && <Message content={message} />}
    </Form>
  )
}
