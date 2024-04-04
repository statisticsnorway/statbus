import React, { useState, useEffect } from 'react'
import { func, arrayOf, shape, string, bool } from 'prop-types'

import LinksGrid from '../Components/LinksGrid/index.jsx'
import LinksForm from '../Components/LinkForm.jsx'
import { defaultUnitSearchResult } from '../Components/UnitSearch.jsx'

function CreateLink({ links, isLoading, params, createLink, deleteLink, localize }) {
  const [data, setData] = useState({
    source1: {
      ...defaultUnitSearchResult,
      id: params ? Number(params.id) : undefined,
      type: params ? Number(params.type) : undefined,
    },
    source2: defaultUnitSearchResult,
    comment: '',
    statUnitType: params ? Number(params.type) : undefined,
    isDeleted: false,
  })

  useEffect(() => {
    setData(prevData => ({
      ...prevData,
      source1: {
        ...prevData.source1,
        id: params ? Number(params.id) : undefined,
        type: params ? Number(params.type) : undefined,
      },
      statUnitType: params ? Number(params.type) : undefined,
    }))
  }, [params])

  const onChange = (value) => {
    setData(value)
  }

  return (
    <div>
      <LinksForm
        data={data}
        isLoading={isLoading}
        onChange={onChange}
        onSubmit={createLink}
        localize={localize}
        submitButtonText="ButtonCreate"
        submitButtonColor="green"
      />
      <LinksGrid localize={localize} data={links} deleteLink={deleteLink} />
    </div>
  )
}

CreateLink.propTypes = {
  links: arrayOf(shape({})).isRequired,
  isLoading: bool.isRequired,
  params: shape({
    id: string,
    type: string,
  }),
  createLink: func.isRequired,
  deleteLink: func.isRequired,
  localize: func.isRequired,
}

CreateLink.defaultProps = {
  params: undefined,
}

export default CreateLink
