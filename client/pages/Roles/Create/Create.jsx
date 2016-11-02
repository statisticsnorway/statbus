import React from 'react'
import { Button, Form, Message } from 'semantic-ui-react'

export default ({ submitRole, message, status }) => {
  const handleSubmit = (e, serialized) => {
    e.preventDefault()
    submitRole(serialized)
  }
  return (
    <div>
      <h2>Create new role</h2>
      <Form onSubmit={handleSubmit}>
        <Form.Input
          name="name"
          label="Role name"
          placeholder="e.g. Web Site Visitor"
        />
        <Form.Input
          name="description"
          label="Description"
          placeholder="e.g. Ordinary website user"
        />
        <Button type="submit" primary>Submit</Button>
        {message && <Message content={message} negative />}
      </Form>
    </div>
  )
}
