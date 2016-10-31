import React from 'react'
import { Button, Form, Message } from 'semantic-ui-react'

// TODO: class component with role fetching in the cDM method
export default ({ role, submitRole, message, status }) => {
  const handleSubmit = (e, serialized) => {
    e.preventDefault()
    submitRole(serialized)
  }
  return role && (
    <Form onSubmit={handleSubmit}>
      <Form.Field>
        <label htmlFor="roleNameInput">Role name</label>
        <input
          id="roleNameInput"
          placeholder="e.g. Web Site Visitor"
          name="name"
          initialValue={role.name}
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="roleDescriptionInput">Description</label>
        <input
          id="roleDescriptionInput"
          placeholder="e.g. Ordinary website user"
          name="description"
          initialValue={role.description}
        />
      </Form.Field>
      <Button type="submit" primary>Submit</Button>
      {message && <Message content={message} />}
    </Form>
  )
}
