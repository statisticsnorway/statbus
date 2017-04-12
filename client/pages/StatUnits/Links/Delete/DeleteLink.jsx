import React from 'react'

import { wrapper } from 'helpers/locale'
import LinksForm from '../Components/LinkForm'

const { func, bool } = React.PropTypes

const DeleteLink = ({ localize, deleteLink, isLoading }) => (
  <div>
    <LinksForm
      isLoading={isLoading}
      onSubmit={deleteLink}
      localize={localize}
      submitButtonText="ButtonCreate"
    />
  </div>
)

DeleteLink.propTypes = {
  localize: func.isRequired,
  deleteLink: func.isRequired,
  isLoading: bool.isRequired,
}

export default wrapper(DeleteLink)
