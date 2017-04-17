import React from 'react'

import { wrapper } from 'helpers/locale'
import LinksGrid from '../Components/LinksGrid'
import LinksForm from '../Components/LinkForm'

const { func, array, bool } = React.PropTypes

const CreateLink = ({ localize, links, createLink, deleteLink, isLoading }) => (
  <div>
    <LinksForm
      isLoading={isLoading}
      onSubmit={createLink}
      localize={localize}
      submitButtonText="ButtonCreate"
    />
    <LinksGrid localize={localize} data={links} deleteLink={deleteLink} />
  </div>
)

CreateLink.propTypes = {
  localize: func.isRequired,
  createLink: func.isRequired,
  deleteLink: func.isRequired,
  links: array.isRequired,
  isLoading: bool.isRequired,
}

export default wrapper(CreateLink)
