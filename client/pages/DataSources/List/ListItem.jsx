import React from 'react'
import { number, string } from 'prop-types'

const ListItem = (
  { id, name, description, priority, allowedOperations },
) => (
  <div>
    {`${id} ${name} ${description} ${priority} ${allowedOperations}`}
  </div>
)

ListItem.propTypes = {
  id: number.isRequired,
  name: string.isRequired,
  description: string,
  priority: number.isRequired,
  allowedOperations: number.isRequired,
}

ListItem.defaultProps = {
  description: '',
}

export default ListItem
