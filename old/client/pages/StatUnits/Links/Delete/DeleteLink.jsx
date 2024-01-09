import React, { useState, useEffect } from 'react'
import { func, bool, shape, string } from 'prop-types'

import LinksForm from '../Components/LinkForm.jsx'
import { defaultUnitSearchResult } from '../Components/UnitSearch.jsx'

function DeleteLink({ localize, deleteLink, isLoading, params }) {
  const [data, setData] = useState({
    source1: {
      ...defaultUnitSearchResult,
      id: params ? Number(params.id) : undefined,
      type: params ? Number(params.type) : undefined,
    },
    source2: defaultUnitSearchResult,
    comment: '',
    statUnitType: params ? Number(params.type) : undefined,
    isDeleted: true,
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

  const onSubmit = (value) => {
    deleteLink(value).then(() => onChange(undefined))
  }

  return (
    <div>
      <LinksForm
        data={data}
        isLoading={isLoading}
        onChange={onChange}
        onSubmit={onSubmit}
        localize={localize}
        submitButtonText="ButtonDelete"
        submitButtonColor="red"
      />
    </div>
  )
}

DeleteLink.propTypes = {
  localize: func.isRequired,
  deleteLink: func.isRequired,
  isLoading: bool.isRequired,
  params: shape({
    id: string,
    type: string,
  }),
}

DeleteLink.defaultProps = {
  params: undefined,
}

export default DeleteLink
